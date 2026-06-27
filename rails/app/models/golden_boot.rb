# Golden boot pool: bet "yes/no" on each round-of-16 team's player who has >= 3
# goals on whether they win the top-scorer race. Shares the champion timing —
# opens when the field is set, each player locks 1h before their team's
# round-of-16 match. Settles off goal data (Scorers.ranked), not match results:
#  - sweep!: a candidate whose team is out and who already trails the leader can
#    never be #1 → settle "no" early. Runs after each goal import.
#  - open_final!: admin reveal once the final's goals are in — top scorer wins.
#
# Golden boot rules (via Scorers.ranked): extra-time goals count, own goals and
# penalty-shootout goals don't (shootout goals never enter openfootball's goals).
module GoldenBoot
  MARKET = "golden_boot"
  MIN_GOALS = 3

  module_function

  # >=3-goal players whose team reached the round of 16, ordered by goals.
  def candidate_subjects
    rows = eligible_rows
    teams = Team.where(id: rows.filter_map(&:team_id)).index_by(&:id)
    rows.map { |row| subject_for(row, teams[row.team_id]) }
  end

  def eligible_rows
    alive = Champion.r16_team_ids
    Scorers.ranked.select { |row| row.goals >= MIN_GOALS && alive.include?(row.team_id) }
  end

  def subject_for(row, team = nil)
    OutrightSubject.new(
      market: MARKET, subject_key: subject_key(row.player_name, row.team_id),
      subject_label: row.player_name, team: team,
      meta: { "team_id" => row.team_id, "goals_at_lock" => row.goals }
    )
  end

  def subject_key(player_name, team_id)
    "scorer:#{team_id}:#{player_name}"
  end

  def open_for?(team_id)
    Champion.open_for?(team_id)
  end

  def leader_goals
    Scorers.ranked.first&.goals || 0
  end

  def winner_row
    Scorers.ranked.first
  end

  # Early "no" settlement: a candidate whose team is eliminated and who trails the
  # leader can no longer add goals, so it can't win the boot. Tied-for-first are
  # left for open_final!. Operates on the actual pools, so it's idempotent and
  # needs no candidate snapshot.
  def sweep!
    leader = leader_goals
    eliminated = TournamentStatus.eliminated_team_ids
    goals_by_key = Scorers.ranked.index_by { |row| subject_key(row.player_name, row.team_id) }

    pooled_subjects.each do |subject_key, team_id, label|
      next if settled?(subject_key)
      next unless team_id && eliminated.include?(team_id)

      row = goals_by_key[subject_key]
      next unless row && row.goals < leader

      settle(subject_key, label, team_id, winning_pick: "no", outcome: "lost")
    end
  end

  # Final reveal — settle every still-open pool: top scorer wins, the rest lose.
  def open_final!(settled_by:)
    top = winner_row
    win_key = top && subject_key(top.player_name, top.team_id)

    pooled_subjects.each do |subject_key, team_id, label|
      next if settled?(subject_key)

      won = subject_key == win_key
      settle(subject_key, label, team_id,
             winning_pick: won ? "yes" : "no", outcome: won ? "won_title" : "lost", settled_by: settled_by)
    end
  end

  # The reveal must run on COMPLETE goal data, but a match's result
  # (football-data.org, ~1 min after final whistle) lands long before its goals
  # (openfootball, re-imported ~every 3h). Gate on the final's goal events
  # reconciling with its recorded score, so the top scorer is read off a fully
  # synced board rather than a half-synced one. A penalty-shootout final needs
  # no shootout goals (they never enter the board, nor the regulation+ET score),
  # so its events already equal the score and it still opens immediately.
  def can_open_final?
    final = Match.find_by(stage: "final")
    return false unless final&.result.present?

    final.goals.count == final.home_score.to_i + final.away_score.to_i
  end

  # Distinct golden-boot subjects that drew bets: [subject_key, team_id, label].
  def pooled_subjects
    OutrightPick.where(market: MARKET)
                .group(:subject_key, :team_id, :subject_label)
                .pluck(:subject_key, :team_id, :subject_label)
  end

  def settled?(subject_key)
    OutrightLedgerEntry.exists?(market: MARKET, subject_key: subject_key)
  end

  def settle(subject_key, label, team_id, winning_pick:, outcome:, settled_by: nil)
    OutrightSettlement.settle!(
      market: MARKET, subject_key: subject_key, subject_label: label, team_id: team_id,
      winning_pick: winning_pick, outcome: outcome, settled_by: settled_by
    )
  end
end
