module OutrightHelper
  MARKET_ICON = { "champion" => "👑", "golden_boot" => "⚽" }.freeze

  def outright_market_label(market)
    I18n.t("outrights.market.#{market}", default: market)
  end

  def outright_market_icon(market)
    MARKET_ICON[market] || ""
  end

  # The yes/no side, framed as the user's 对/否 wager.
  def outright_pick_label(pick)
    I18n.t("outrights.pick.#{pick == 'yes' ? 'yes' : 'no'}")
  end

  # What actually happened to the subject, for the settled-row sub-line.
  def outright_result_label(market, outcome)
    case [ market, outcome ]
    in [ "champion", "won_title" ] then I18n.t("outrights.result.champion.won")
    in [ "champion", _ ] then I18n.t("outrights.result.champion.lost")
    in [ "golden_boot", "won_title" ] then I18n.t("outrights.result.golden_boot.won")
    else I18n.t("outrights.result.golden_boot.lost")
    end
  end

  # 赢 / 退（push, no counterparty）/ 请（owe）.
  def outright_delta_verb(delta)
    return I18n.t("outrights.delta.push") if delta.zero?

    I18n.t(delta.positive? ? "outrights.delta.win" : "outrights.delta.owe")
  end

  # Stable, DOM-safe id for a candidate card — subject_key carries spaces/colons
  # (player names, "team:5"), so it can't be a raw id.
  def outright_dom_id(market, subject_key)
    "oc_#{market}_#{Digest::SHA1.hexdigest(subject_key)[0, 12]}"
  end

  # Polymarket champion probability as a percent string (nil → no market). Tiny
  # long-shot odds show as "<1%" rather than rounding to a misleading "0%".
  def outright_market_pct(prob)
    return nil unless prob

    pct = prob * 100
    return "<1%" if pct.positive? && pct < 1

    "#{pct.round}%"
  end

  # Crowd-implied champion probability from the pari-mutuel 对/否 pool: the share
  # of bottles backing "对" (this team wins). nil when nobody has bet yet.
  def outright_crowd_pct(tally)
    total = tally.yes + tally.no
    total.positive? ? "#{(tally.yes / total * 100).round}%" : nil
  end

  # Coarse "还有约 X" for the server-rendered countdown; the countdown Stimulus
  # controller then ticks a precise value client-side.
  def outright_countdown_text(deadline)
    seconds = (deadline - Time.current).to_i
    return I18n.t("outrights.countdown.closed") if seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3_600
    minutes = (seconds % 3_600) / 60
    return I18n.t("outrights.countdown.days_hours", days: days, hours: hours) if days.positive?
    return I18n.t("outrights.countdown.hours_minutes", hours: hours, minutes: minutes) if hours.positive?

    I18n.t("outrights.countdown.minutes", minutes: minutes)
  end
end
