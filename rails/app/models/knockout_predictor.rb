# Turns a knockout placeholder label ("2A", "1E", "3A/B/C/D/F", "W74") into the
# team(s) it would currently resolve to, based on live group standings. This is a
# DISPLAY-ONLY soft link: the real matchup still arrives via the schedule sync
# (which sets home_team_id/away_team_id); a prediction is only shown while a slot
# is unresolved. Build once per render and reuse — it reads the cached group
# tables, so repeated predicts across a page are cheap.
class KnockoutPredictor
  POSITION_RE = /\A([12])([A-L])\z/                 # 1A / 2B → group winner / runner-up
  THIRD_RE = %r{\A3([A-L](?:/[A-L])*)\z}            # 3A/B/C/D/F → best-third candidates
  WINNER_RE = /\A([WL])(\d+)\z/                     # W74 / L101 → winner / loser of a match

  # Knockout rounds, shallowest first. The Final is predictable too (a team's
  # path is shown all the way through), where each side spans a whole bracket
  # half — a deliberately wide "possible finalists" list. Only the third-place
  # play-off stays unpredicted.
  STAGE_ORDER = %w[r32 r16 qf sf final].freeze
  PREDICTABLE_STAGES = %w[r32 r16 qf sf final].freeze
  PREDICT_DEPTH = 4                                 # frontier round + next three (through the Final)

  Prediction = Struct.new(:kind, :row, :candidates, keyword_init: true)
  # `position` is the team's current 1/2/3 placing in its group (for multi rows);
  # `rank`/`qualified` are the cross-group third-place ranking (for third slots).
  Candidate = Struct.new(:row, :group_letter, :rank, :qualified, :position, keyword_init: true)

  def initialize
    @tables = Standings::Group.tables
    ranked = Standings::ThirdPlace.ranked(@tables)
    @third_rank = ranked.index_by { |entry| entry.row.team_id }
    index_teams
    load_knockout
    @slot_assignment = assign_thirds_to_slots(ranked)
  end

  # A Prediction, or nil when nothing can be inferred yet (a slot in a round
  # beyond the prediction window, or a group with no teams yet).
  def predict(label)
    return nil if label.blank?

    if (match = POSITION_RE.match(label))
      row = @tables.dig(match[2], match[1].to_i - 1)
      row && Prediction.new(kind: :team, row: row)
    elsif THIRD_RE.match?(label)
      candidates = third_candidates(label)
      Prediction.new(kind: :candidates, candidates: candidates) if candidates.any?
    elsif (match = WINNER_RE.match(label))
      multi_prediction(label, match[2].to_i)
    end
  end

  private

  # A "many possible teams" prediction for a winner/loser slot (W74, L101): every
  # team that could reach that match, but only while the round it feeds is inside
  # the live prediction window (see #predict_window). Each unresolved upstream
  # third-place slot collapses to its single most-likely team, so the set stays a
  # clean binary-tree size (R16 2, QF 4, SF 8 per side).
  def multi_prediction(label, match_num)
    return nil unless @window.include?(@slot_stage[label])

    candidates = participants(match_num).filter_map { |team_id| team_candidate(team_id) }
    Prediction.new(kind: :multi, candidates: candidates) if candidates.any?
  end

  # The candidates shown for this slot, in the slot's own fixed group order
  # (A→B→C…, as the label lists them) — a stable order that does not reshuffle as
  # results land. The third assigned to this slot by the live one-to-one
  # allocation (#assign_thirds_to_slots) is pulled to the front — it is the
  # predicted opponent, so the same third never LEADS more than one slot, though
  # it may still sit in another slot's pool. With no full allocation yet, the
  # best-ranked third leads.
  def third_candidates(label)
    candidates = label_groups(label).filter_map { |letter|
      row = @tables.dig(letter, 2)
      next unless row

      entry = @third_rank[row.team_id]
      Candidate.new(
        row: row, group_letter: letter, position: 3,
        rank: entry&.rank, qualified: entry&.qualified || false
      )
    }

    lead = @slot_assignment[label] ||
      candidates.min_by { |candidate| candidate.rank || Float::INFINITY }&.group_letter
    if lead && (index = candidates.find_index { |candidate| candidate.group_letter == lead })
      candidates.unshift(candidates.delete_at(index))
    end
    candidates
  end

  # FIFA's Annex C allocation: the eight qualifying third-placed teams fill the
  # eight third-place slots one-to-one (each from a group its slot allows, never
  # its own), looked up from the official 495-row table by the set of qualifying
  # groups. Returns {slot_label => group_letter}, or {} when fewer than eight
  # thirds are decided yet (or the combination is missing); callers then fall back
  # to plain cross-group order.
  def assign_thirds_to_slots(ranked)
    qualifying = ranked.select(&:qualified).map(&:letter)
    return {} unless qualifying.size == Standings::ThirdPlace::QUALIFYING_SLOTS

    assignment = ThirdPlaceAllocation.assignment(qualifying)
    return {} unless assignment

    assignment.filter_map { |match_num, group_letter|
      label = third_label_for(match_num)
      [ label, group_letter ] if label
    }.to_h
  end

  # The best-third slot label a given knockout match number hosts (74 ->
  # "3A/B/C/D/F"), or nil if that match isn't loaded or isn't a third-place slot.
  def third_label_for(match_num)
    match = @ko_by_num[match_num]
    return nil unless match

    [ match.home_label, match.away_label ].find { |label| THIRD_RE.match?(label.to_s) }
  end

  def label_groups(label)
    THIRD_RE.match(label)[1].split("/")
  end

  # team_id => its group Row / group letter, for resolving knockout participants
  # back to a displayable team.
  def index_teams
    @row_by_team = {}
    @group_of_team = {}
    @tables.each do |letter, rows|
      rows.each do |row|
        @row_by_team[row.team_id] = row
        @group_of_team[row.team_id] = letter
      end
    end
  end

  # Load the knockout bracket (match number => match), record which round each
  # winner/loser slot feeds, and compute the live prediction window.
  def load_knockout
    matches = Match.where(stage: STAGE_ORDER + %w[third]).to_a
    @ko_by_num = {}
    @slot_stage = {}
    matches.each do |match|
      num = match.external_key[/\Am:(\d+)/, 1]&.to_i
      @ko_by_num[num] = match if num
      [ match.home_label, match.away_label ].compact.each do |slot|
        @slot_stage[slot] = match.stage if WINNER_RE.match?(slot)
      end
    end
    @window = predict_window(matches)
    @participants = {}
  end

  # The rounds we currently predict: the frontier (shallowest knockout round
  # whose teams aren't all decided) plus the next two, capped before the Final.
  def predict_window(matches)
    by_stage = matches.group_by(&:stage)
    frontier = STAGE_ORDER.find do |stage|
      (by_stage[stage] || []).any? { |match| match.home_team_id.nil? || match.away_team_id.nil? }
    end
    return [] unless frontier

    STAGE_ORDER[STAGE_ORDER.index(frontier), PREDICT_DEPTH] & PREDICTABLE_STAGES
  end

  # Every team that could play in match `num`: the union of both sides' possible
  # teams. A resolved side is itself; an unresolved side is recursively expanded
  # (1A/2B → that group's team, a third-place slot → its single most-likely team,
  # W/L → the fed match's participants). Memoised, with a re-entrancy guard.
  def participants(num)
    return @participants[num] if @participants.key?(num)

    @participants[num] = []
    match = @ko_by_num[num]
    return [] unless match

    ids = side_team_ids(match.home_team_id, match.home_label) +
          side_team_ids(match.away_team_id, match.away_label)
    @participants[num] = ids.uniq
  end

  def side_team_ids(team_id, label)
    return [ team_id ] if team_id
    return [] if label.blank?

    if (match = POSITION_RE.match(label))
      row = @tables.dig(match[2], match[1].to_i - 1)
      row ? [ row.team_id ] : []
    elsif THIRD_RE.match?(label)
      lead = third_candidates(label).first
      lead ? [ lead.row.team_id ] : []
    elsif (match = WINNER_RE.match(label))
      participants(match[2].to_i)
    else
      []
    end
  end

  def team_candidate(team_id)
    letter = @group_of_team[team_id]
    row = @row_by_team[team_id]
    return nil unless row

    position = @tables[letter]&.index { |group_row| group_row.team_id == team_id }
    Candidate.new(row: row, group_letter: letter, position: position && position + 1)
  end
end
