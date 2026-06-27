# Derives team-level tournament progress from match results — no status column
# to maintain. Shared by the champion pool (display + settlement) and the golden
# boot early-settlement sweep.
module TournamentStatus
  module_function

  # team_ids of every knockout loser so far. A team is eliminated the instant it
  # loses a knockout match; r32 losers are included too (harmless — they hold no
  # champion pool and the golden boot sweep only acts on actual candidates).
  def eliminated_team_ids
    Match.where(stage: Match::KNOCKOUT_STAGES.to_a).where.not(result: nil)
         .includes(:home_team, :away_team)
         .filter_map { |match| match.loser_team&.id }
         .to_set
  end

  def champion_team_id
    Match.find_by(stage: "final")&.winner_team&.id
  end
end
