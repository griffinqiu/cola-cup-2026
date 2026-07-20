# One-off data fix. The final 西班牙 vs 阿根廷 (Spain vs Argentina) finished 1:0,
# but its lone scorer never reached us: football-data.org owns the score (synced
# within a minute of the final whistle), while openfootball owns the goal events
# — and openfootball still hasn't published the final. Its Final entry carries no
# `score`/`goals` keys at all, so ImportScheduleJob imports nothing for it. The
# result is a final with a scoreline but zero goal rows, which:
#   1. leaves the top-scorer board missing the final's scorer, and
#   2. blocks the golden-boot reveal — GoldenBoot.can_open_final? requires
#      final.goals.count == home_score + away_score, i.e. exactly 1 here.
#
# Seed that single goal — Ferran Torres García (西班牙), his only goal of the
# tournament, scored as a substitute in the 106th minute (extra time) — so the
# board shows it and the reveal
# button unblocks. This does NOT settle the golden boot: an admin still clicks
# ⚽ 金靴开奖 on /admin/settlements?tab=records (the top scorer is 姆巴佩 with 10,
# unbeaten since the final adds only this 1 goal to a Spain player on ≤8).
#
# The final is located by stage + team (not a hard-coded m:NN, which differs per
# environment) and every step is guarded to act ONLY on the exact state — a final
# recorded 西班牙 1 : 0 对手, with no goals yet — so a re-run, a hand-fix, an env
# that never had this fixture, or (crucially) CI/test and fresh dev DBs are all a
# safe no-op. When openfootball finally publishes the final, ImportScheduleJob's
# sync_goals delete_all's this row and re-inserts the authoritative version, so
# this is self-healing. Runs automatically on the next deploy
# (bin/docker-entrypoint -> db:prepare applies pending migrations).
class SeedFinalScorerFerranTorres < ActiveRecord::Migration[8.1]
  SCORER = "Ferran Torres García".freeze

  def up
    final = Match.find_by(stage: "final")
    return say("no final match — nothing to seed") if final.nil?
    return say("final has no recorded result yet — nothing to seed") if final.result.blank?

    spain = Team.find_by(name: "Spain")
    return say("Spain team missing — nothing to seed") if spain.nil?

    if final.home_team_id == spain.id
      spain_score, opp_score = final.home_score.to_i, final.away_score.to_i
    elsif final.away_team_id == spain.id
      spain_score, opp_score = final.away_score.to_i, final.home_score.to_i
    else
      return say("Spain is not in the final (#{final.home_team_id} vs #{final.away_team_id}) — skipping")
    end

    # Guard: only seed when the recorded scoreline is exactly 西班牙 1 : 0 对手, so
    # this lone Spain goal reconciles the board (final.goals.count == total score).
    # Any other scoreline means more goals are missing than we know — bail rather
    # than write a half-synced final.
    unless spain_score == 1 && opp_score == 0
      return say("final is not the '西班牙 1 : 0' state (Spain #{spain_score}, opponent #{opp_score}) — skipping")
    end

    # Idempotent: any existing goal on the final (our seed on a re-run, or the real
    # openfootball data having landed) means there is nothing to seed.
    if final.goals.exists?
      return say("final already has #{final.goals.count} goal(s) — already synced, skipping")
    end

    Match.transaction do
      Goal.create!(match: final, team: spain, player_name: SCORER,
                   minute: 106, penalty: false, own_goal: false)
    end
    say("seeded #{SCORER} (西班牙) as the final's scorer — GoldenBoot.can_open_final? => #{GoldenBoot.can_open_final?}")
    say("next: an admin opens /admin/settlements?tab=records and clicks ⚽ 金靴开奖 to settle 姆巴佩 as the golden boot")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
