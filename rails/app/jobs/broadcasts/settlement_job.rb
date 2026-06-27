module Broadcasts
  # A settlement was committed: refresh every settled match's schedule card and
  # detail page, the leaderboard, each affected bettor's /me ledger, and the
  # admin. Per-bettor ledgers use refresh+morph so each viewer re-renders with
  # their own session.
  class SettlementJob < ApplicationJob
    include Renderable
    queue_as :default

    def perform(settlement_id)
      settlement = Settlement.find_by(id: settlement_id)
      return unless settlement

      settlement.matches.includes(:home_team, :away_team).each do |match|
        broadcast_card_meta(match)
        broadcast_card_teams(match)
        broadcast_card_big(match)
        broadcast_refresh_each_locale("match", match)
      end

      broadcast_leaderboard

      settlement.payouts.each do |payout|
        broadcast_refresh_each_locale(payout.user, "ledger") if payout.user
      end

      broadcast_refresh_each_locale("admin")
    end
  end
end
