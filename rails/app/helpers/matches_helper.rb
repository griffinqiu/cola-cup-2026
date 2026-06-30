module MatchesHelper
  # status (Match#status symbol) => css modifier. The badge label is localized
  # (matches.status.*) and resolved in #status_badge. upcoming reuses the
  # "scheduled" badge styling. Ported from matchState.ts STATUS_META.
  STATUS_CSS = {
    scheduled: "scheduled",
    upcoming:  "scheduled",
    open:      "open",
    live:      "live",
    locked:    "locked",
    settled:   "settled"
  }.freeze

  GROUP_RE = /Group ([A-L])/.freeze

  # Short pick glyph (主/平/客), localized.
  def pick_short(pick)
    I18n.t("matches.pick_short.#{pick}")
  end

  # Pick-button label sizing. A button is one of three equal columns, so on the
  # narrowest phone layout its inner text is ~78px wide; a CJK glyph is roughly
  # 1em, giving this per-button width budget. Long country names (沙特阿拉伯,
  # 乌兹别克斯坦) shrink to stay on one line instead of wrapping and stretching
  # the whole button row taller.
  PICK_LABEL_MAX_FONT_PX = 20
  PICK_LABEL_MIN_FONT_PX = 11
  PICK_LABEL_FIT_WIDTH_PX = 78

  def status_badge(status, extra_class: nil)
    css = STATUS_CSS.fetch(status)
    label = I18n.t("matches.status.#{status}")
    tag.span(label, class: [ "badge", css, extra_class ].compact.join(" "))
  end

  # 焦点大战: top Polymarket-volume unsettled matches. Memoized per render so a
  # full schedule page costs one query; broadcast re-renders work the same way.
  def focus_match?(match)
    @_focus_match_ids ||= PolyMarket.focus_match_ids
    @_focus_match_ids.include?(match.id)
  end

  def match_group_letter(match)
    match.group_name&.match(GROUP_RE)&.captures&.first
  end

  def team_display_name(team, label)
    team&.display_name.presence || label.presence || ""
  end

  def team_flag(team)
    team&.flag.presence || "🏳️"
  end

  # Detail-page team cell (flag + name). A resolved team links to its fixtures
  # page; an unresolved knockout slot shows a soft-link prediction (single team,
  # or the top third-place candidate with the rest expandable) marked "预测",
  # else a readable label.
  def detail_team_cell(team, label)
    return link_to(team_flag_name(team), team_path(team), class: "team") if team

    case (prediction = slot_prediction(team, label))&.kind
    when :team
      group_link(row_flag_name_code(prediction.row, label), label_group(label), "team predicted")
    when :candidates
      detail_candidate_cell(prediction.candidates)
    when :multi
      detail_multi_cell(prediction.candidates)
    else
      group_link(tag.span(humanize_slot_label(label), class: "nm placeholder"), label_group(label), "team")
    end
  end

  # Schedule-card team cell inner (compact). Resolved team → flag + name; an
  # unresolved knockout slot → predicted team / the top third-place candidate / a
  # readable label fallback. Used by matches/_card_teams (broadcast-safe: only
  # needs `match`, computes the predictor on its own).
  def card_team_html(team, label)
    return team_flag_name(team) if team

    case (prediction = slot_prediction(team, label))&.kind
    when :team
      group_link(row_flag_name_code(prediction.row, label), label_group(label))
    when :candidates
      top = prediction.candidates.first
      group_link(row_flag_name_code(top.row, slot_code(top)), top.group_letter)
    when :multi
      multi_flags(prediction.candidates)
    else
      group_link(tag.span(humanize_slot_label(label), class: "nm placeholder"), label_group(label))
    end
  end

  # The third-place candidate list for a knockout card's expandable disclosure,
  # or nil when neither side is an unresolved third-place slot.
  def card_candidate_prediction(match)
    [ [ match.home_team, match.home_label ], [ match.away_team, match.away_label ] ]
      .filter_map { |team, label| slot_prediction(team, label) }
      .find { |prediction| prediction.kind == :candidates }&.candidates
  end

  # The unresolved [label, possible-teams] sides of a deeper-round (W/L) card —
  # used to fill its expandable disclosure with each side's possible countries —
  # or nil when neither side is a many-teams prediction.
  def card_multi_sides(match)
    [ [ match.home_team, match.home_label ], [ match.away_team, match.away_label ] ]
      .filter_map { |team, label|
        prediction = slot_prediction(team, label)
        [ label, prediction.candidates ] if prediction&.kind == :multi
      }.presence
  end

  # Per-render predictor; reused across every card on a page (like focus_match?).
  def knockout_predictor
    @_knockout_predictor ||= KnockoutPredictor.new
  end

  # Prediction for an unresolved slot, or nil (resolved team, blank label, or
  # nothing inferable like a winner-of-match slot).
  def slot_prediction(team, label)
    return nil if team || label.blank?

    knockout_predictor.predict(label)
  end

  # Readable fallback for a slot we can't predict yet: "A 组第2" / "A/B/C/D/F 组第3"
  # / "M74 胜者" / the raw label.
  def humanize_slot_label(label)
    return "" if label.blank?

    if (match = /\A([12])([A-L])\z/.match(label))
      I18n.t("matches.slot.group_position", group: match[2], position: match[1])
    elsif label.start_with?("3") && label[1..].match?(%r{\A[A-L](/[A-L])*\z})
      I18n.t("matches.slot.third_place", groups: label[1..])
    elsif (match = /\AW(\d+)\z/.match(label))
      I18n.t("matches.slot.match_winner", match: match[1])
    else
      label
    end
  end

  def team_flag_name(team)
    safe_join([
      tag.span(team_flag(team), class: "flag"),
      tag.span(team.display_name, class: "nm")
    ])
  end

  # Same, from a denormalized Standings::Row (knockout predictions).
  def row_flag(row)
    row.flag.presence || "🏳️"
  end

  def row_flag_name(row)
    safe_join([
      tag.span(row_flag(row), class: "flag"),
      tag.span(row.display_name, class: "nm")
    ])
  end

  # An uncertain (predicted) team: flag + name + its slot code (1A / 2B / 3C). The
  # name is dashed-underlined (via .predicted) to read as a guess, not a fixture.
  def row_flag_name_code(row, code)
    safe_join([ row_flag_name(row), tag.span(code, class: "slot-code") ])
  end

  # A team's "position + group" slot code from its current standing: 1A (group
  # winner), 2B (runner-up), 3C (third). The shared notation for every predicted
  # team, whoever lists it.
  def slot_code(candidate)
    "#{candidate.position}#{candidate.group_letter}"
  end

  # Link a predicted-team display to its group's table; a plain span when there's
  # no single group to point at (e.g. a "W97" winner-of slot).
  def group_link(content, letter, css = nil)
    return tag.span(content, class: css) unless letter.present?

    link_to(content, group_path(letter), class: css)
  end

  # The single group letter a label points at (1A/2B → A/B); nil for multi-group
  # or match-winner labels (3A/B/.., W97).
  def label_group(label)
    label.to_s[/\A[12]([A-L])\z/, 1]
  end

  # Detail-page third-place slot: the predicted opponent shown up top (linking to
  # its group), with an expandable list of ALL candidates — the predicted one
  # included — plus a link to the full third-place ranking.
  def detail_candidate_cell(candidates)
    top = candidates.first
    inner = [ group_link(row_flag_name_code(top.row, slot_code(top)), top.group_letter, "cand-top") ]
    inner << candidate_disclosure(candidates) if candidates.size > 1
    inner << link_to(I18n.t("matches.candidates.full_ranking"), third_place_path, class: "cand-more")
    tag.span(safe_join(inner), class: "team predicted is-candidates")
  end

  # Expandable list of all third-place candidates for this slot (the predicted
  # opponent first, then the rest), in the slot's fixed group order.
  def candidate_disclosure(candidates)
    tag.details(class: "cand-disclosure") do
      safe_join([
        tag.summary(safe_join([ "#{I18n.t('matches.candidates.summary')} ", tag.span("▸", class: "kc-caret") ]), class: "cand-disc-summary"),
        tag.div(candidate_list_rows(candidates), class: "cand-list detail-cand-list")
      ])
    end
  end

  # Candidate rows in the slot's fixed group order. Each row carries its own
  # 线上 / 线下 tag, and teams currently below the qualifying line are dimmed —
  # the live picture reads at a glance without the list reordering as results land
  # (a 线下 team can still climb above the line later).
  def candidate_list_rows(candidates)
    safe_join(candidates.map { |candidate| candidate_row(candidate) })
  end

  def candidate_row(candidate)
    content = safe_join([
      tag.span(row_flag(candidate.row), class: "flag"),
      tag.span(candidate.row.display_name, class: "nm"),
      tag.span(slot_code(candidate), class: "slot-code"),
      tag.span(I18n.t(candidate.qualified ? "matches.candidates.online" : "matches.candidates.offline"), class: [ "cand-st", candidate.qualified ? "in" : "out" ].join(" "))
    ])
    group_link(content, candidate.group_letter, [ "cand-row", candidate.qualified ? "in" : "out" ].join(" "))
  end

  # Collapsed view of a deeper-round (W/L) slot: just the flags of every team that
  # could fill it — names live one tap away in the expandable disclosure.
  def multi_flags(candidates)
    tag.span(safe_join(candidates.map { |candidate| tag.span(row_flag(candidate.row), class: "flag") }), class: "multi-flags")
  end

  # Detail-page deeper-round cell: flags up top, an expandable list of every
  # possible team (name + group) below.
  def detail_multi_cell(candidates)
    disclosure = tag.details(class: "cand-disclosure") do
      safe_join([
        tag.summary(safe_join([ "#{I18n.t('matches.candidates.summary_count', count: candidates.size)} ", tag.span("▸", class: "kc-caret") ]), class: "cand-disc-summary"),
        tag.div(multi_rows(candidates), class: "cand-list detail-cand-list")
      ])
    end
    tag.span(safe_join([ multi_flags(candidates), disclosure ]), class: "team predicted is-multi")
  end

  # Name rows (flag + name + slot code) for a deeper-round slot's possible teams,
  # each linking to that team's group table.
  def multi_rows(candidates)
    safe_join(candidates.map { |candidate|
      content = safe_join([
        tag.span(row_flag(candidate.row), class: "flag"),
        tag.span(candidate.row.display_name, class: "nm"),
        tag.span(slot_code(candidate), class: "slot-code")
      ])
      group_link(content, candidate.group_letter, "cand-row multi-row")
    })
  end

  # The "VS" / score middle token on a schedule card (shows the score as soon as
  # it is recorded).
  def match_score_token(match)
    if match.home_score && match.away_score
      "#{match.home_score}–#{match.away_score}#{penalty_token(match)}"
    else
      "VS"
    end
  end

  # Detail-page middle token — shows the live score while in play and the final
  # score once settled; hides it in between so a pre-settlement correction
  # isn't presented as final.
  def detail_score_token(match)
    if (match.settled? || match.live?) && match.home_score && match.away_score
      "#{match.home_score}–#{match.away_score}#{penalty_token(match)}"
    else
      "VS"
    end
  end

  # "（点 2:3）" appended to a knockout score decided on penalties; "" otherwise.
  # The level full-time score alone would read as an unresolved draw, so the
  # shootout digits make the advancing side legible.
  def penalty_token(match)
    return "" unless match.pen_home && match.pen_away

    "（#{t('matches.penalty_score')} #{match.pen_home}:#{match.pen_away}）"
  end

  # Font size (px) for a pick-button label, shrinking long names to one line.
  def pick_label_font_px(label)
    length = label.to_s.length
    return PICK_LABEL_MAX_FONT_PX if length <= 4

    (PICK_LABEL_FIT_WIDTH_PX / length).clamp(PICK_LABEL_MIN_FONT_PX, PICK_LABEL_MAX_FONT_PX)
  end

  # Decimal pool odds for each valid pick AS IF the current viewer's fixed stake
  # already sat on that pick — their existing vote (if any) is moved onto the
  # pick before the pool is divided. Raw crowd odds ignore the viewer's own
  # stake, so a side nobody has backed yet (e.g. 平 when only 葡萄牙 has votes)
  # shows no payout, when picking it would in fact win the existing pool. Returns
  # pick => decimal (>= 1.0); exactly 1.0 means there's no opposing pool to win.
  def preview_odds_by_pick(match, tally, current_pick, stake: match.default_stake)
    viewer_in_pool = current_pick ? stake : 0.0
    others_total = tally.stake_total - viewer_in_pool

    match.valid_picks.index_with do |pick|
      others_on_pick = tally.public_send(pick) - (current_pick == pick ? stake : 0.0)
      (others_total + stake) / (others_on_pick + stake)
    end
  end

  # The crowd pool with the viewer's own existing stake removed, handed to the
  # JS so it can recompute the payout for whatever bottle amount the player
  # selects (knockout stakes are no longer fixed):
  #   odds(pick, s)      = (others_total + s) / (others_on_pick + s)
  #   potential(pick, s) = s * (others_total - others_on_pick) / (others_on_pick + s)
  def preview_pool(match, tally, user_vote)
    viewer_stake = user_vote&.stake.to_f
    others_total = tally.stake_total - viewer_stake
    by_pick = match.valid_picks.index_with do |pick|
      tally.public_send(pick) - (user_vote&.pick == pick ? viewer_stake : 0.0)
    end
    { others_total: others_total, by_pick: by_pick }
  end

  # Outcome label for a pick: the team's display name, or 平局 for a draw.
  def pick_team_label(match, key)
    case key
    when "home" then team_display_name(match.home_team, match.home_label)
    when "away" then team_display_name(match.away_team, match.away_label)
    else I18n.t("matches.result_label.draw")
    end
  end

  # Describes the giant right-hand block on a schedule card. Mirrors
  # ScheduleTimeline.MatchBig: result > market leader (+divergence) > crowd
  # leader > nothing.
  def match_card_big(match, tally, market_snapshot)
    # No cap once settled — the meta line's status badge already says settled.
    return { kind: :result, label: Match.pick_label(match.result), cap: match.settled? ? nil : I18n.t("matches.pending_settlement") } if match.result.present?

    allows_draw = match.allows_draw?
    market = market_pcts(market_snapshot, allows_draw)
    leader = market && market_leader(market)
    if leader
      return {
        kind: :market,
        short: pick_short(leader[:pick]),
        pct: leader[:pct],
        divergence: divergence_label(match, market, tally, allows_draw, leader[:pick])
      }
    end

    crowd = crowd_leader(tally, allows_draw)
    if crowd
      crowd_odds = VoteOdds.from_tally(tally, allows_draw: allows_draw)
      decimal = crowd_odds&.public_send("d_#{crowd[:pick]}")
      return {
        kind: :crowd,
        short: pick_short(crowd[:pick]),
        pct: crowd[:pct],
        cap: decimal ? I18n.t("matches.odds_multiplier", odds: format_decimal(decimal)) : I18n.t("matches.no_market_comparison")
      }
    end

    { kind: :none }
  end

  # --- detail-page odds comparison (ported from OddsCompare.tsx) ---

  def odds_clamp_width(probability)
    return 0 if probability.nil?

    (probability.clamp(0.0, 1.0) * 100).round
  end

  def odds_pct_text(probability)
    probability.nil? ? "—" : "#{(probability.clamp(0.0, 1.0) * 100).round}%"
  end

  # Outcome to feature (largest bar): highest market probability, else highest
  # crowd probability, else -1.
  def odds_featured_index(outcomes)
    max_index_by(outcomes) { |o| o[:market_p] } ||
      max_index_by(outcomes) { |o| o[:crowd_p] } || -1
  end

  # Outcome with the widest market-vs-crowd gap (crowd must have stake).
  def odds_lead_index(outcomes)
    best_index = -1
    best_diff = -1
    outcomes.each_with_index do |o, i|
      next if o[:crowd_p].nil? || o[:crowd_p] <= 0 || o[:market_p].nil?

      diff = (o[:market_p] - o[:crowd_p]).abs
      best_index, best_diff = i, diff if diff > best_diff
    end
    best_index
  end

  def odds_lead_label(crowd_p, market_p, featured)
    return nil if crowd_p.nil? || market_p.nil?

    diff = ((market_p - crowd_p) * 100).round
    return nil if diff.abs < VoteOdds::LEAD_DIVERGENCE_PCT

    if diff > 0
      tag.span(I18n.t("matches.odds_lead.market"), class: [ "o-lead", "mk-lead", ("strong" if featured) ].compact.join(" "))
    else
      tag.span(I18n.t("matches.odds_lead.crowd"), class: "o-lead cr-lead")
    end
  end

  private

  def max_index_by(outcomes)
    best_index = nil
    best_value = nil
    outcomes.each_with_index do |o, i|
      value = yield(o)
      next if value.nil?

      best_index, best_value = i, value if best_value.nil? || value > best_value
    end
    best_index
  end

  def odds_pct(probability)
    probability.nil? ? nil : (probability * 100).round
  end

  def market_pcts(snapshot, allows_draw)
    return nil unless snapshot

    {
      "home" => odds_pct(snapshot.p_home),
      "draw" => allows_draw ? odds_pct(snapshot.p_draw) : nil,
      "away" => odds_pct(snapshot.p_away)
    }
  end

  def market_leader(market)
    best = nil
    Match::PICKS.each do |pick|
      value = market[pick]
      next if value.nil?
      best = { pick: pick, pct: value } if best.nil? || value > best[:pct]
    end
    best
  end

  def crowd_leader(tally, allows_draw)
    return nil unless tally.stake_total.positive?

    entries = { "home" => tally.home, "draw" => allows_draw ? tally.draw : -1, "away" => tally.away }
    pick, value = entries.max_by { |_, v| v }
    { pick: pick, pct: (value / tally.stake_total * 100).round }
  end

  # Largest market-vs-crowd gap; returns the spark label when it clears the
  # LEAD_DIVERGENCE_PCT threshold, else nil.
  def divergence_label(_match, market, tally, allows_draw, leader_pick)
    best = nil
    Match::PICKS.each do |pick|
      market_pct = market[pick]
      crowd_pct = crowd_pct_for(tally, pick, allows_draw)
      next if market_pct.nil? || crowd_pct.nil? || crowd_pct <= 0

      diff = market_pct - crowd_pct
      best = { pick: pick, diff: diff } if best.nil? || diff.abs > best[:diff].abs
    end
    return nil if best.nil? || best[:diff].abs < VoteOdds::LEAD_DIVERGENCE_PCT

    market_leads = best[:diff] > 0
    same_as_shown = best[:pick] == leader_pick
    lead = I18n.t(market_leads ? "matches.odds_lead.market" : "matches.odds_lead.crowd")
    text = lead + (same_as_shown ? "" : pick_short(best[:pick]))
    { tone: market_leads ? "mk" : "cr", text: text }
  end

  def crowd_pct_for(tally, pick, allows_draw)
    return nil if tally.voters.zero?
    return nil if pick == "draw" && !allows_draw

    (tally.public_send(pick) / tally.stake_total * 100).round
  end
end
