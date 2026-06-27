# Enqueued (per knockout match) the moment a result is recorded — alongside
# AutoSettleJob, which settles the match's win/lose votes. Settles the champion
# pools the result decides: the eliminated team, and (for the final) the
# champion. Idempotent — Champion.settle_for_match no-ops on an already-settled
# subject, so this is safe to run more than once.
class ChampionSettleJob < ApplicationJob
  queue_as :default

  def self.schedule(match)
    perform_later(match.id)
  end

  def perform(match_id)
    match = Match.includes(:home_team, :away_team).find_by(id: match_id)
    return if match.nil? || match.result.blank?

    Champion.settle_for_match(match)
  end
end
