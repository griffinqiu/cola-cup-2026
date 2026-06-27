module AdminHelper
  # Outcome groups [pick, label] for a match's roster, in home/[draw]/away order.
  def roster_groups(match)
    groups = [ [ "home", team_display_name(match.home_team, match.home_label) ] ]
    groups << [ "draw", I18n.t("matches.result_label.draw") ] if match.allows_draw?
    groups << [ "away", team_display_name(match.away_team, match.away_label) ]
    groups
  end

  def result_team_name(match, pick)
    case pick
    when "home" then team_display_name(match&.home_team, match&.home_label).presence || I18n.t("matches.result_label.home")
    when "away" then team_display_name(match&.away_team, match&.away_label).presence || I18n.t("matches.result_label.away")
    else I18n.t("matches.result_label.draw")
    end
  end

  # Stakes are whole bottles in practice — drop the ".0" so chips read "1🥤".
  def stake_label(stake)
    stake.to_i == stake ? stake.to_i : stake
  end

  # Unsigned bottle total for the settlement-record header.
  def bottles_label(value)
    format("%.1f", value)
  end

  # Whether a voter is opted into this match's settlement, given the submitted
  # `included` map. A missing key defaults to checked (settle everyone).
  def roster_checked?(included, match_id, user_id)
    raw = included && (included[match_id.to_s] || included[match_id])
    return true unless raw.is_a?(Array)

    raw.map(&:to_i).include?(user_id.to_i)
  end
end
