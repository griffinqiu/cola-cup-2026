# Champion pool: bet "yes/no" on each of the 16 round-of-16 teams winning the
# cup. Betting opens the moment the round-of-16 field is set and each team locks
# 1h before *its own* round-of-16 match (not a single global cutoff). Settles
# off match results: a team's pool settles the moment it's knocked out; the
# final's winner settles "yes".
module Champion
  MARKET = "champion"
  CHAMPION_STAGES = %w[r16 qf sf final].freeze
  LOCK_LEAD = 1.hour

  module_function

  # The 16 round-of-16 teams as uniform subjects. Computed live — the field is
  # fixed once set, and per-team deadlines (not a snapshot) govern locking.
  def candidate_subjects
    Match.where(stage: "r16").includes(:home_team, :away_team).order(:kickoff_at)
         .flat_map { |match| [ match.home_team, match.away_team ] }
         .compact.uniq.map { |team| subject_for(team) }
  end

  def subject_for(team)
    OutrightSubject.new(market: MARKET, subject_key: subject_key(team.id),
                        subject_label: team.name_zh.presence || team.name,
                        team: team, meta: { "team_id" => team.id })
  end

  def subject_key(team_id)
    "team:#{team_id}"
  end

  # The market is live the moment the *first* round-of-16 team is known — you can
  # bet each team as it's determined, no need to wait for the full field. Drives
  # whether the tab, promo and page appear.
  def available?
    Match.where(stage: "r16").where("home_team_id IS NOT NULL OR away_team_id IS NOT NULL").exists?
  end

  def r16_team_ids
    Match.where(stage: "r16").pluck(:home_team_id, :away_team_id).flatten.compact.to_set
  end

  def r16_kickoff_for(team_id)
    return nil if team_id.nil?

    Match.where(stage: "r16")
         .where("home_team_id = :id OR away_team_id = :id", id: team_id)
         .minimum(:kickoff_at)
  end

  # A team locks 1h before its own round-of-16 match.
  def deadline_for(team_id)
    kickoff = r16_kickoff_for(team_id)
    kickoff && kickoff - LOCK_LEAD
  end

  # { team_id => deadline } for every round-of-16 team, in one query — avoids an
  # N+1 when the board scores open/locked for each candidate.
  def deadlines_by_team
    kickoffs = {}
    Match.where(stage: "r16").pluck(:home_team_id, :away_team_id, :kickoff_at).each do |home, away, kickoff|
      [ home, away ].compact.each do |team_id|
        kickoffs[team_id] = [ kickoffs[team_id], kickoff ].compact.min
      end
    end
    kickoffs.transform_values { |kickoff| kickoff - LOCK_LEAD }
  end

  # Betting on this team is allowed as soon as it's in the round of 16 (it has a
  # deadline) and until that deadline. Golden boot shares the team's deadline.
  def open_for?(team_id)
    deadline = deadline_for(team_id)
    deadline.present? && Time.current < deadline
  end

  # Called when a knockout match's result is recorded (see ChampionSettleJob).
  def settle_for_match(match)
    return unless CHAMPION_STAGES.include?(match.stage) && match.result.present?

    if (loser = match.loser_team)
      settle_team(loser, winning_pick: "no", outcome: "lost", match: match)
    end
    return unless match.stage == "final" && (winner = match.winner_team)

    settle_team(winner, winning_pick: "yes", outcome: "won_title", match: match)
  end

  def settle_team(team, winning_pick:, outcome:, match:)
    OutrightSettlement.settle!(
      market: MARKET, subject_key: subject_key(team.id),
      subject_label: team.name_zh.presence || team.name, team_id: team.id,
      winning_pick: winning_pick, outcome: outcome, source_match_id: match.id
    )
  end
end
