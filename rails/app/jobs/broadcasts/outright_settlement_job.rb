module Broadcasts
  # After an outright subject settles, fan out exactly like SettlementJob does
  # for a match: refresh the predictions page, the global leaderboard, each
  # affected bettor's personal ledger, and the admin.
  class OutrightSettlementJob < ApplicationJob
    include Renderable
    queue_as :default

    def perform(user_ids)
      Turbo::StreamsChannel.broadcast_refresh_to("predictions")
      broadcast_leaderboard

      User.where(id: user_ids).find_each do |user|
        Turbo::StreamsChannel.broadcast_refresh_to(user, "ledger")
      end

      Turbo::StreamsChannel.broadcast_refresh_to("admin")
    end
  end
end
