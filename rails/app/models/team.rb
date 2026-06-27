class Team < ApplicationRecord
  has_many :home_matches, class_name: "Match", foreign_key: :home_team_id, dependent: :nullify, inverse_of: :home_team
  has_many :away_matches, class_name: "Match", foreign_key: :away_team_id, dependent: :nullify, inverse_of: :away_team

  validates :name, presence: true, uniqueness: true

  # Localized team name for display. `name` (English) stays the third-party
  # matching key (openfootball / football-data / Polymarket) and is never
  # translated in the DB; translation happens only here at render time:
  #   en    -> English `name`
  #   zh-CN -> the seeded `name_zh`
  #   zh-TW / ja -> i18n `teams.<English name>` (config/locales/teams.*.yml),
  #                 falling back to name_zh / name when a team isn't listed.
  def display_name
    case I18n.locale.to_s
    when "en" then name
    when "zh-CN" then name_zh.presence || name
    else I18n.t(name, scope: :teams, default: name_zh.presence || name)
    end
  end
end
