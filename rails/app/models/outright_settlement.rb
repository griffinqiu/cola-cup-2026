# Settles one outright subject's yes/no pool via the shared pari-mutuel split and
# writes the frozen ledger rows. Pure mechanism: the champion / golden-boot
# drivers decide *when* and *who won*; this just transfers the cola.
#
# Idempotent twice over: an early `exists?` guard plus the unique
# (user_id, market, subject_key) index on insert_all — a subject settles once.
module OutrightSettlement
  module_function

  # winning_pick: "yes" (won the title) or "no" (eliminated / didn't win).
  def settle!(market:, subject_key:, subject_label:, team_id:, winning_pick:,
              outcome:, source_match_id: nil, settled_by: nil)
    return false if OutrightLedgerEntry.exists?(market: market, subject_key: subject_key)

    picks = OutrightPick.active.where(market: market, subject_key: subject_key).to_a
    return false if picks.empty?

    now = Time.current
    rows = PariMutuel.deltas(picks, winning_pick).map do |delta|
      {
        user_id: delta.user_id, market: market, subject_key: subject_key,
        subject_label: subject_label, team_id: team_id, pick: delta.pick,
        stake: delta.stake, d_used: delta.d_used, won: delta.won, delta: delta.delta,
        outcome: outcome, source_match_id: source_match_id,
        settled_by_id: settled_by&.id, settled_at: now, created_at: now, updated_at: now
      }
    end

    OutrightLedgerEntry.insert_all(rows, unique_by: [ :user_id, :market, :subject_key ])
    Broadcasts::OutrightSettlementJob.perform_later(rows.map { |row| row[:user_id] }.uniq)
    true
  end
end
