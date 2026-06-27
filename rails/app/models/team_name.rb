# Localizes an English team name with the rules shared by every place a team is
# shown (Team records and the denormalized Standings/Scorers value rows alike).
# `name` (English) stays the canonical third-party matching key and is never
# stored translated; translation happens here at render time:
#   en          -> English `name`
#   zh-CN       -> seeded `name_zh`
#   zh-TW / ja  -> i18n `teams.<English name>` (config/locales/teams.*.yml),
#                  falling back to name_zh / name when a team isn't listed.
module TeamName
  module_function

  def localized(name, name_zh)
    case I18n.locale.to_s
    when "en" then name
    when "zh-CN" then name_zh.presence || name
    else I18n.t(name, scope: :teams, default: name_zh.presence || name)
    end
  end
end
