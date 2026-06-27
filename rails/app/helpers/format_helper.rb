module FormatHelper
  # All kickoff/schedule times render in Beijing time regardless of the server
  # timezone (UTC in the container) or the viewer's locale. Ported from the
  # legacy src/lib/format.ts (+ decimalOdds.formatDecimal, ScheduleTimeline.dayHeading).
  DISPLAY_TIME_ZONE = "Asia/Shanghai".freeze

  EM_DASH = "—".freeze

  # Stable YYYY-MM-DD key in Beijing time, used to group matches by day.
  def day_key(time)
    in_display_zone(time).strftime("%Y-%m-%d")
  end

  # Schedule day heading. Per-locale format (zh-CN "6月11日 周四", en "Thu, Jun
  # 11"); %a resolves to the locale's abbreviated weekday.
  def format_day_label(time)
    I18n.l(in_display_zone(time), format: :day_label)
  end

  # Match-detail kickoff line, per-locale (zh-CN "6/11 11:00 周四").
  def format_kickoff(time)
    I18n.l(in_display_zone(time), format: :kickoff)
  end

  # 24h, zero-padded, e.g. "11:00" / "00:00".
  def format_time_only(time)
    in_display_zone(time).strftime("%H:%M")
  end

  # Countdown copy relative to now, localized. Reads "已开赛" / "Kicked off" once
  # the kickoff has passed.
  def format_countdown(time, now = Time.current)
    seconds = time.to_i - now.to_i
    return I18n.t("format.countdown.started") if seconds <= 0

    days = seconds / 86_400
    hours = (seconds % 86_400) / 3_600
    minutes = (seconds % 3_600) / 60
    return I18n.t("format.countdown.days_hours", days: days, hours: hours) if days.positive?
    return I18n.t("format.countdown.hours_minutes", hours: hours, minutes: minutes) if hours.positive?

    I18n.t("format.countdown.minutes", minutes: minutes)
  end

  # Net bottles with an explicit "+" for positive balances. "+2.50" / "-1.00" /
  # "0.00". Two decimals so a settled payout renders exactly as stored.
  def format_bottles(value)
    number = value.to_f
    number = 0.0 if number.zero? # collapse -0.0, matching JS (-0).toFixed(2)
    sign = number.positive? ? "+" : ""
    "#{sign}#{to_fixed(number, 2)}"
  end

  # Bottle counts (stakes) printed like a JS number: whole values drop the
  # decimal ("1.0" => "1"), fractional values keep it ("2.5" => "2.5").
  def bottles_count(value)
    number = value.to_f
    number == number.to_i ? number.to_i.to_s : number.to_s
  end

  # Decimal odds to two places; nil / non-finite renders as an em dash.
  def format_decimal(value)
    return EM_DASH if value.nil?

    number = value.to_f
    return EM_DASH unless number.finite?

    to_fixed(number, 2)
  end

  # Odds-snapshot timestamp, e.g. "6/13 08:00" — the date keeps a stale market
  # line honest, no weekday so it stays tag-sized.
  def format_snapshot_time(time)
    I18n.l(in_display_zone(time), format: :snapshot)
  end

  # Beijing date + time (no weekday) for the rate-limit reset, e.g. "6月11日 11:00".
  def format_reset_time(epoch_seconds)
    t = Time.zone.at(epoch_seconds.to_i).in_time_zone(DISPLAY_TIME_ZONE)
    I18n.l(t, format: :reset)
  end

  # Relative day heading mirroring the legacy ScheduleTimeline.dayHeading.
  # Returns [primary_label_or_nil, is_today]; nil primary means "use the date label".
  def relative_day_heading(date_key, today_key)
    return [ I18n.t("format.relative_day.today"), true ]      if date_key == today_key
    return [ I18n.t("format.relative_day.tomorrow"), false ]  if date_key == day_key_offset(today_key, 1)
    return [ I18n.t("format.relative_day.yesterday"), false ] if date_key == day_key_offset(today_key, -1)

    [ nil, false ]
  end

  # Shift a YYYY-MM-DD key by whole days, preserving zero-padding.
  def day_key_offset(today_key, offset_days)
    (Date.iso8601(today_key) + offset_days).strftime("%Y-%m-%d")
  end

  private

  def in_display_zone(time)
    time.in_time_zone(DISPLAY_TIME_ZONE)
  end

  # Fixed-decimal string matching JS Number#toFixed for all real-world values
  # (round half away from zero). Pure float ties such as 2.05/0.15 — which never
  # arise from computed pari-mutuel/odds data — may differ in the last place.
  def to_fixed(number, digits)
    format("%.#{digits}f", number.round(digits))
  end
end
