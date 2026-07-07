# Champion pool: bet "yes/no" on each knockout team (from the round of 32 on)
# winning the cup. Betting opens the moment a team reaches the round of 32 and
# locks 1h before *that team's own* quarter-final. A team still alive but not yet
# slotted into a quarter-final stays open (no countdown); an eliminated team is
# closed and its pool settles "no". Settles off match results: a team's pool
# settles the moment it's knocked out; the final's winner settles "yes".
module Champion
  MARKET = "champion"
  CHAMPION_STAGES = %w[r32 r16 qf sf final].freeze
  # Betting opens as a team reaches OPEN_STAGE and locks 1h before its LOCK_STAGE match.
  OPEN_STAGE = "r32"
  LOCK_STAGE = "qf"
  LOCK_LEAD = 1.hour

  module_function

  # Every knockout team (round of 32 onward) as a uniform subject, ordered by
  # kickoff. Eliminated teams stay in the list (shown closed); per-team
  # quarter-final deadlines govern locking.
  def candidate_subjects
    Match.where(stage: OPEN_STAGE).includes(:home_team, :away_team).order(:kickoff_at)
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

  # The market is live the moment the *first* round-of-32 team is known — you can
  # bet each team as it's determined, no need to wait for the full field. Drives
  # whether the tab, promo and page appear.
  def available?
    Match.where(stage: OPEN_STAGE).where("home_team_id IS NOT NULL OR away_team_id IS NOT NULL").exists?
  end

  # The knockout field (round-of-32 teams) — also the golden-boot candidate gate.
  def knockout_team_ids
    Match.where(stage: OPEN_STAGE).pluck(:home_team_id, :away_team_id).flatten.compact.to_set
  end

  def qf_kickoff_for(team_id)
    return nil if team_id.nil?

    Match.where(stage: LOCK_STAGE)
         .where("home_team_id = :id OR away_team_id = :id", id: team_id)
         .minimum(:kickoff_at)
  end

  # A team locks 1h before its own quarter-final. nil until it's slotted into one
  # (still alive earlier in the bracket, or eliminated before reaching it).
  def deadline_for(team_id)
    kickoff = qf_kickoff_for(team_id)
    kickoff && kickoff - LOCK_LEAD
  end

  # { team_id => deadline } for every team already slotted into a quarter-final,
  # in one query — avoids an N+1 when the board scores open/locked per candidate.
  def deadlines_by_team
    kickoffs = {}
    Match.where(stage: LOCK_STAGE).pluck(:home_team_id, :away_team_id, :kickoff_at).each do |home, away, kickoff|
      [ home, away ].compact.each do |team_id|
        kickoffs[team_id] = [ kickoffs[team_id], kickoff ].compact.min
      end
    end
    kickoffs.transform_values { |kickoff| kickoff - LOCK_LEAD }
  end

  # Betting on this team is allowed from the moment it reaches the round of 32
  # until 1h before its own quarter-final — but never once it's knocked out. A
  # team not yet slotted into a quarter-final has no deadline and stays open.
  # Golden boot shares this gate (and the team's deadline).
  def open_for?(team_id)
    return false if TournamentStatus.eliminated_team_ids.include?(team_id)

    deadline = deadline_for(team_id)
    deadline.nil? || Time.current < deadline
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
