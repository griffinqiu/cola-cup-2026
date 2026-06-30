# One-off data fix. On 2026-06-29 the Round-of-32 fixture 荷兰 vs 摩洛哥
# (Netherlands home, Morocco away — m:75) finished 1:1 and Morocco won the penalty
# shootout 3:2. football-data briefly reported it FINISHED with winner "DRAW"
# before backfilling the shootout result, so derive_result produced "draw" and we
# recorded + settled it as a knockout draw. Two things are wrong on disk:
#   - the match row carries result "draw" (impossible for a knockout), and
#   - the pari-mutuel ledger settled as a push (nobody backs "draw", so every
#     stake was refunded) — the cola that should move from 荷兰 backers to 摩洛哥
#     backers never moved.
# Advancement is already correct: every downstream consumer reads
# `result == "home" ? home : away`, so "draw" advanced Morocco (away) into the
# Round of 16 and eliminated Netherlands in the champion pool just the same. Only
# the match-level settlement needs correcting, by re-running it on the real "away"
# result.
#
# This runs automatically on the next deploy (bin/docker-entrypoint -> db:prepare
# applies pending migrations) and is guarded so it only acts on the exact buggy
# state — a re-run, or a hand-correction beforehand, is a no-op.
class FixNetherlandsMoroccoKnockoutDraw < ActiveRecord::Migration[8.1]
  EXTERNAL_KEY = "m:75".freeze

  def up
    match = Match.find_by(external_key: EXTERNAL_KEY)
    return say("#{EXTERNAL_KEY} not found — nothing to fix") if match.nil?

    # Sanity: this fix is specific to Netherlands(home) vs Morocco(away). If the
    # slot resolved to anything else, leave it untouched.
    unless match.home_team&.name == "Netherlands" && match.away_team&.name == "Morocco"
      return say(
        "#{EXTERNAL_KEY} is #{match.home_team&.name.inspect} vs #{match.away_team&.name.inspect}, " \
        "not Netherlands vs Morocco — skipping"
      )
    end

    # Guard: only touch the precise bug state — a knockout recorded as a 1:1 draw.
    # Anything else (already corrected to away, hand-fixed, or re-run) is left alone.
    unless match.home_score == 1 && match.away_score == 1 && match.result == "draw"
      return say(
        "#{EXTERNAL_KEY} not in the 1:1/draw bug state " \
        "(now #{match.home_score.inspect}:#{match.away_score.inspect}/#{match.result.inspect}) — skipping"
      )
    end

    Match.transaction do
      # Re-settle the cola from the actual participants. The ledger rows ARE the
      # set that was settled (respecting any per-voter filter the settler used) and
      # respond to user_id/pick/stake, so PariMutuel recomputes directly off them
      # with the corrected "away" (Morocco advances) result — turning the push into
      # the real transfer from 荷兰 backers to 摩洛哥 backers. The match keeps its
      # settled flag and settlement record; the history view reads the ledger live.
      # The new ledger ids advance User.leaderboard_signature, so the cached
      # leaderboard self-invalidates and shows the corrected cola.
      if match.settled? && match.ledger_entries.exists?
        now = Time.current
        rows = PariMutuel.deltas(match.ledger_entries.to_a, "away").map do |d|
          {
            match_id: match.id, user_id: d.user_id, pick: d.pick, stake: d.stake,
            d_used: d.d_used, won: d.won, delta: d.delta, created_at: now, updated_at: now
          }
        end
        match.ledger_entries.delete_all
        LedgerEntry.insert_all(rows) if rows.any?
        say("re-settled #{rows.size} ledger row(s) on the corrected away (Morocco) result")
      end

      # Correcting result keeps the 1:1 scoreline (the shootout never changes
      # full-time) and broadcasts the change to open clients. winner_team is still
      # Morocco (away), so the Round-of-16 slot and champion pool stay correct.
      match.update!(home_score: 1, away_score: 1, result: "away")
      say("corrected #{EXTERNAL_KEY} to 1:1, Morocco advancing")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
