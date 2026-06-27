module Standings
  # Bump to invalidate every cached table after a logic change to the computation.
  CACHE_VERSION = "v1".freeze

  # One team's line in a group table. Team identity is denormalized (id + names +
  # flag) so a Row is a plain value object that serializes into the cache without
  # dragging an ActiveRecord object along. Points and goal difference are derived.
  Row = Struct.new(
    :team_id, :name, :name_zh, :flag,
    :played, :won, :drawn, :lost, :goals_for, :goals_against,
    keyword_init: true
  ) do
    def points
      won * 3 + drawn
    end

    def goal_diff
      goals_for - goals_against
    end

    def display_name
      TeamName.localized(name, name_zh)
    end
  end

  # FIFA table ordering: points, then goal difference, then goals scored. Team
  # name is the final, deterministic tiebreaker (fair-play points and drawing of
  # lots are out of scope — no disciplinary data; cross-group thirds never met).
  SORT_KEY = ->(row) { [ -row.points, -row.goal_diff, -row.goals_for, row.name ] }

  # Cache-key fragment that changes whenever the tables could change: any group
  # match's updated_at (a recorded or edited score bumps it), the count of played
  # group matches, and team rows (a corrected flag/name). So a cached table
  # self-expires on the next result — nothing ever needs to clear it by hand.
  def self.signature
    group = Match.where(stage: "group")
    [
      CACHE_VERSION,
      group.maximum(:updated_at)&.to_f,
      group.where.not(result: nil).count,
      Team.maximum(:updated_at)&.to_f
    ].join("-")
  end
end
