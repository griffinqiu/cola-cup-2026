module Scorers
  # One player's line in the top-scorer board. Team identity is denormalized
  # (id + names + flag) so a Row is a plain value object that renders without
  # dragging an ActiveRecord object along — the same convention as Standings::Row.
  Row = Struct.new(
    :player_name, :team_id, :name, :name_zh, :flag,
    :goals, :penalties, :matches,
    keyword_init: true
  ) do
    def display_name
      TeamName.localized(name, name_zh)
    end
  end

  # Golden Boot ordering: goals, then (since openfootball carries no assists or
  # minutes played for FIFA's real tiebreakers) fewer penalties favours open-play
  # scorers, with the player name as the final deterministic tiebreaker.
  SORT_KEY = ->(row) { [ -row.goals, row.penalties, row.player_name ] }

  # Own goals never count toward a player's tally. Goals are grouped by
  # (player_name, team_id) so two players who share a name on different national
  # teams stay distinct. Computed live from the goals table on each request,
  # mirroring how the standings tables are derived from matches.
  def self.ranked
    grouped = Goal.where(own_goal: false)
                  .group(:player_name, :team_id)
                  .select(
                    "player_name",
                    "team_id",
                    "COUNT(*) AS goals",
                    "SUM(CASE WHEN penalty THEN 1 ELSE 0 END) AS penalties",
                    "COUNT(DISTINCT match_id) AS matches_scored"
                  )
    teams = Team.where(id: grouped.filter_map(&:team_id).uniq).index_by(&:id)

    grouped.map { |group| build_row(group, teams[group.team_id]) }.sort_by(&SORT_KEY)
  end

  def self.build_row(group, team)
    Row.new(
      player_name: group.player_name,
      team_id: group.team_id,
      name: team&.name,
      name_zh: team&.name_zh,
      flag: team&.flag,
      goals: group.goals,
      penalties: group.penalties.to_i,
      matches: group.matches_scored
    )
  end
end
