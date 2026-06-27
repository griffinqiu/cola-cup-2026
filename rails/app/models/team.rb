class Team < ApplicationRecord
  has_many :home_matches, class_name: "Match", foreign_key: :home_team_id, dependent: :nullify, inverse_of: :home_team
  has_many :away_matches, class_name: "Match", foreign_key: :away_team_id, dependent: :nullify, inverse_of: :away_team

  validates :name, presence: true, uniqueness: true

  # Localized team name for display. The locale rules live in TeamName so the
  # denormalized Standings/Scorers value rows localize identically.
  def display_name
    TeamName.localized(name, name_zh)
  end
end
