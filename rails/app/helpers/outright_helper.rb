module OutrightHelper
  MARKET_LABEL = { "champion" => "猜冠军", "golden_boot" => "金靴奖" }.freeze
  MARKET_ICON = { "champion" => "👑", "golden_boot" => "⚽" }.freeze

  def outright_market_label(market)
    MARKET_LABEL[market] || market
  end

  def outright_market_icon(market)
    MARKET_ICON[market] || ""
  end

  # The yes/no side, framed as the user's 对/否 wager.
  def outright_pick_label(pick)
    pick == "yes" ? "对" : "否"
  end

  # What actually happened to the subject, for the settled-row sub-line.
  def outright_result_label(market, outcome)
    case [ market, outcome ]
    in [ "champion", "won_title" ] then "夺冠"
    in [ "champion", _ ] then "出局"
    in [ "golden_boot", "won_title" ] then "金靴"
    else "无缘金靴"
    end
  end

  # 赢 / 退（push, no counterparty）/ 请（owe）.
  def outright_delta_verb(delta)
    return "退" if delta.zero?

    delta.positive? ? "赢" : "请"
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
    return "已封盘" if seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3_600
    minutes = (seconds % 3_600) / 60
    return "#{days} 天 #{hours} 小时" if days.positive?
    return "#{hours} 小时 #{minutes} 分" if hours.positive?

    "#{minutes} 分"
  end
end
