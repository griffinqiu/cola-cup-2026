# Commits resolved knockout matchups to the database — the write-side counterpart
# to the display-only KnockoutPredictor. A slot is filled only once its outcome is
# CERTAIN, never from a provisional standing:
#
#   W##/L##      the fed match has a result, so winner/loser is final. Resolved
#                locally from recorded results — the openfootball import is told not
#                to overwrite these (see ScheduleImport#merged_team_id).
#   1A/2B        that group's matches are all played, so its final placing is fixed.
#   3A/B/C/...   every group is played, so the eight best thirds and their FIFA
#                Annex C slot assignment are fixed.
#
# Writes team ids only — never result/score/settled — and skips a side that already
# holds a team, so it is idempotent and safe to re-run. The per-result
# KnockoutAdvanceJob runs it live; the 3h ImportScheduleJob runs it as a backstop.
# One pass walks the bracket shallow-to-deep, so a freshly filled round feeds the
# next one in the same run.
class KnockoutResolver
  GROUP_PREFIX = "Group "

  def self.run
    new.run
  end

  def initialize
    @matches = Match.where(stage: Match::KNOCKOUT_STAGES).to_a
    @by_num = @matches.index_by { |match| match.external_key[/\Am:(\d+)/, 1]&.to_i }
  end

  # Fills every newly-decided slot; returns the number of matches updated.
  def run
    @matches.sort_by { |match| Match::STAGES.index(match.stage) }
      .sum { |match| fill(match) ? 1 : 0 }
  end

  private

  def fill(match)
    return false if match.home_team_id && match.away_team_id

    match.home_team_id ||= resolve(match.home_label)
    match.away_team_id ||= resolve(match.away_label)
    return false unless match.changed?

    match.save!
    true
  end

  def resolve(label)
    label = label.to_s
    if (winner = KnockoutPredictor::WINNER_RE.match(label))
      resolve_winner(winner[1], winner[2].to_i)
    elsif (position = KnockoutPredictor::POSITION_RE.match(label))
      resolve_position(position[2], position[1].to_i - 1)
    elsif KnockoutPredictor::THIRD_RE.match?(label)
      resolve_third(label)
    end
  end

  # Read team ids straight off the source (not winner_team/loser_team) so a source
  # resolved earlier in this same pass is seen without an association reload.
  def resolve_winner(side, match_number)
    source = @by_num[match_number]
    return nil if source.nil? || source.result.blank?

    home_advances = source.result == "home"
    winner_id = home_advances ? source.home_team_id : source.away_team_id
    loser_id = home_advances ? source.away_team_id : source.home_team_id
    side == "W" ? winner_id : loser_id
  end

  def resolve_position(letter, index)
    return nil unless group_complete?(letter)

    tables.dig(letter, index)&.team_id
  end

  def resolve_third(label)
    return nil unless all_groups_complete?

    letter = third_assignment[label]
    letter && tables.dig(letter, 2)&.team_id
  end

  def tables
    @tables ||= Standings::Group.tables
  end

  # The Annex C opponent group for each third-place slot label, e.g.
  # { "3A/B/C/D/F" => "D" }. Empty until all eight qualifying thirds are decided.
  def third_assignment
    @third_assignment ||= begin
      ranked = Standings::ThirdPlace.ranked(tables)
      qualifying = ranked.select(&:qualified).map(&:letter)
      allocation = qualifying.size == Standings::ThirdPlace::QUALIFYING_SLOTS &&
        ThirdPlaceAllocation.assignment(qualifying)
      (allocation || {}).each_with_object({}) do |(match_number, letter), slots|
        label = third_label_for(match_number)
        slots[label] = letter if label
      end
    end
  end

  def third_label_for(match_number)
    match = @by_num[match_number]
    return nil unless match

    [ match.home_label, match.away_label ].find { |label| KnockoutPredictor::THIRD_RE.match?(label.to_s) }
  end

  def group_complete?(letter)
    completion["#{GROUP_PREFIX}#{letter}"] || false
  end

  def all_groups_complete?
    return @all_groups_complete unless @all_groups_complete.nil?

    @all_groups_complete = completion.any? && completion.values.all?
  end

  # group_name => every match in it has a result. One query, evaluated in Ruby so
  # it stays database-agnostic.
  def completion
    @completion ||= Match.where(stage: "group").where.not(group_name: nil)
      .pluck(:group_name, :result)
      .group_by(&:first)
      .transform_values { |rows| rows.all? { |(_, result)| result.present? } }
  end
end
