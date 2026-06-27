# One-off data fix. On 2026-06-26 the live-score source briefly reported the
# Group G fixture 埃及 vs 伊朗 (Egypt home, Iran away) as a 1:2 away win (Iran)
# when it actually finished 1:1. The bad scoreline was settled, so three things
# are wrong on disk: the match row, the group standings (derived from it — they
# self-correct once the row is fixed), and the pari-mutuel ledger that paid out
# the cola.
#
# This runs automatically on the next deploy (bin/docker-entrypoint -> db:prepare
# applies pending migrations) and is guarded so it only acts on the exact buggy
# state — a re-run, or a hand-correction beforehand, is a no-op.
class FixIranEgyptGroupGScore < ActiveRecord::Migration[8.1]
  EXTERNAL_KEY = "Matchday 16|2026-06-26|Egypt|Iran".freeze

  def up
    match = Match.find_by(external_key: EXTERNAL_KEY)
    return say("#{EXTERNAL_KEY} not found — nothing to fix") if match.nil?

    # Guard: only touch the precise scoreline the bad source recorded — Egypt 1,
    # Iran 2 (away win). Anything else (already a draw, hand-corrected, or re-run)
    # is left untouched.
    unless match.home_score == 1 && match.away_score == 2 && match.result == "away"
      return say(
        "#{EXTERNAL_KEY} not in the 1:2/away bug state " \
        "(now #{match.home_score.inspect}:#{match.away_score.inspect}/#{match.result.inspect}) — skipping"
      )
    end

    Match.transaction do
      # Re-settle the cola from the actual participants. The ledger rows ARE the
      # set that was settled (respecting any per-voter filter the settler used),
      # and respond to user_id/pick/stake, so PariMutuel recomputes directly off
      # them with the corrected "draw" result. The match keeps its settled flag
      # and settlement record; the history view reads the ledger live.
      if match.settled? && match.ledger_entries.exists?
        now = Time.current
        rows = PariMutuel.deltas(match.ledger_entries.to_a, "draw").map do |d|
          {
            match_id: match.id, user_id: d.user_id, pick: d.pick, stake: d.stake,
            d_used: d.d_used, won: d.won, delta: d.delta, created_at: now, updated_at: now
          }
        end
        match.ledger_entries.delete_all
        LedgerEntry.insert_all(rows) if rows.any?
        say("re-settled #{rows.size} ledger row(s) on the corrected 1:1 draw")
      end

      # Correcting result + home_score bumps updated_at, which rolls
      # Standings.signature, so the group table / points / ranking / knockout
      # predictor all self-correct. update! also broadcasts the new score to
      # any open clients.
      match.update!(home_score: 1, away_score: 1, result: "draw")
      say("corrected #{EXTERNAL_KEY} to 1:1 (draw)")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
