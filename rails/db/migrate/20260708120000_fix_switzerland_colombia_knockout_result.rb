# One-off data fix. 2026-07-08: the knockout tie 瑞士 vs 哥伦比亚 (Switzerland vs
# Colombia) actually finished 0:0 and 瑞士 won the penalty shootout 4:3, advancing
# to meet 阿根廷 (Argentina) in the next round. But the result recorded on disk was
# a 0:1 regulation win for 哥伦比亚, so Match#record_result! fanned the WRONG winner
# out through three consumers, each of which is corrected here:
#   1. AutoSettleJob settled the match's pari-mutuel ledger on 哥伦比亚 winning.
#   2. KnockoutResolver filled the next-round slot (W<n>) with 哥伦比亚 — the tie
#      read "阿根廷 vs 哥伦比亚" instead of "阿根廷 vs 瑞士".
#   3. ChampionSettleJob settled 瑞士's champion pool as eliminated ("no"), and the
#      goal-import golden-boot sweep may have settled 瑞士's scorer pools "no" early
#      too — while 哥伦比亚 (the side actually knocked out) never settled.
#
# Everything is re-derived from the correct "瑞士 advances" result. The tie is
# located by team (not a hard-coded m:NN, which differs per environment) and every
# step is guarded to act ONLY on the exact bug state — 哥伦比亚 recorded as the
# knockout winner — so a re-run, a hand-fix, or an environment that never had this
# fixture is a safe no-op. Runs automatically on the next deploy
# (bin/docker-entrypoint -> db:prepare applies pending migrations).
class FixSwitzerlandColombiaKnockoutResult < ActiveRecord::Migration[8.1]
  def up
    swiss = Team.find_by(name: "Switzerland")
    colombia = Team.find_by(name: "Colombia")
    return say("Switzerland/Colombia team missing — nothing to fix") unless swiss && colombia

    match = knockout_tie(swiss, colombia)
    return say("no knockout 瑞士 vs 哥伦比亚 fixture — nothing to fix") if match.nil?

    swiss_home = match.home_team_id == swiss.id
    correct_result = swiss_home ? "home" : "away"   # 瑞士 advances
    wrong_result   = swiss_home ? "away" : "home"   # 哥伦比亚 wrongly advanced

    unless match.result == wrong_result
      return say(
        "#{match.external_key} result=#{match.result.inspect} is not the 哥伦比亚-advanced " \
        "bug state (expected #{wrong_result.inspect}) — skipping"
      )
    end

    Match.transaction do
      resettle_match_ledger(match, correct_result)
      correct_scoreline(match, swiss_home)
      fix_next_round_slot(match, swiss, colombia)
      fix_outright_pools(match, swiss)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def knockout_tie(swiss, colombia)
    Match.where(stage: Match::KNOCKOUT_STAGES.to_a)
         .where(
           "(home_team_id = :s AND away_team_id = :c) OR (home_team_id = :c AND away_team_id = :s)",
           s: swiss.id, c: colombia.id
         ).first
  end

  # Re-settle the match cola from the actual participants on the corrected result.
  # The ledger rows ARE the settled set (respecting any per-voter filter the settler
  # used) and respond to user_id/pick/stake, so PariMutuel recomputes directly off
  # them — turning the payout to 哥伦比亚 backers into the real transfer to 瑞士
  # backers. The match keeps its settled flag and settlement record; the history
  # view reads the ledger live, and the new ledger ids roll the leaderboard cache.
  def resettle_match_ledger(match, correct_result)
    return unless match.settled? && match.ledger_entries.exists?

    now = Time.current
    rows = PariMutuel.deltas(match.ledger_entries.to_a, correct_result).map do |d|
      {
        match_id: match.id, user_id: d.user_id, pick: d.pick, stake: d.stake,
        d_used: d.d_used, won: d.won, delta: d.delta, created_at: now, updated_at: now
      }
    end
    match.ledger_entries.delete_all
    LedgerEntry.insert_all(rows) if rows.any?
    say("re-settled #{rows.size} match ledger row(s) on the corrected #{correct_result} (瑞士 advancing)")
  end

  # 0:0 full time, shootout 瑞士 4:3. Writing pen_* only when the column exists keeps
  # this safe on an older schema. update! broadcasts the new score to open clients.
  def correct_scoreline(match, swiss_home)
    attrs = { home_score: 0, away_score: 0, result: (swiss_home ? "home" : "away") }
    if Match.column_names.include?("pen_home")
      attrs[:pen_home] = swiss_home ? 4 : 3
      attrs[:pen_away] = swiss_home ? 3 : 4
    end
    match.update!(attrs)
    pen = attrs[:pen_home] ? " (pen #{attrs[:pen_home]}:#{attrs[:pen_away]})" : ""
    say("corrected #{match.external_key} to 0:0#{pen}, 瑞士 advancing")
  end

  # KnockoutResolver only fills EMPTY slots, so the slot it wrongly filled with
  # 哥伦比亚 won't self-correct on a re-run — repoint it to 瑞士 here. Only an
  # unsettled next-round match is safe to repoint; a settled one (the error already
  # cascaded further) is flagged for manual review rather than silently rewritten.
  def fix_next_round_slot(match, swiss, colombia)
    num = match.external_key[/\Am:(\d+)/, 1]
    return say("#{match.external_key} has no m:NN number — locate the next-round slot manually") if num.nil?

    slot = "W#{num}"
    Match.where(stage: Match::KNOCKOUT_STAGES.to_a).each do |nxt|
      fixes = {}
      fixes[:home_team_id] = swiss.id if nxt.home_label == slot && nxt.home_team_id == colombia.id
      fixes[:away_team_id] = swiss.id if nxt.away_label == slot && nxt.away_team_id == colombia.id
      next if fixes.empty?

      if nxt.settled?
        say("WARNING: next-round #{nxt.external_key} already settled with 哥伦比亚 in #{slot} — manual review needed")
      else
        nxt.update!(fixes)
        say("fixed next-round #{nxt.external_key}: slot #{slot} 哥伦比亚 → 瑞士")
      end
    end
  end

  # Champion + golden-boot pools: drop the rows that settled 瑞士 as knocked out,
  # then let the shared champion driver settle 哥伦比亚 (the side actually eliminated).
  # Deleting a non-existent row is a harmless no-op, and settle_for_match is
  # idempotent (exists? guard), so this is safe on any environment / re-run.
  def fix_outright_pools(match, swiss)
    champ = OutrightLedgerEntry.where(market: Champion::MARKET, team_id: swiss.id).delete_all
    say("reverted #{champ} champion ledger row(s) wrongly settling 瑞士 as eliminated") if champ.positive?

    boot = OutrightLedgerEntry.where(market: GoldenBoot::MARKET, team_id: swiss.id).delete_all
    say("reverted #{boot} golden-boot ledger row(s) for 瑞士 players settled 'no' early") if boot.positive?

    Champion.settle_for_match(match.reload)
    say("settled 哥伦比亚 champion pool as eliminated (no-op if no bets)")
  end
end
