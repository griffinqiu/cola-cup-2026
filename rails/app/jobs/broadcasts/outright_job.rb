module Broadcasts
  # A pick change (or the lock) moves the pools shown on the predictions page;
  # refresh it for every viewer via Turbo morphing, the same way SettlementJob
  # refreshes match pages. Args are accepted but unused — any change refreshes
  # the whole page.
  class OutrightJob < ApplicationJob
    queue_as :default

    def perform(*)
      Turbo::StreamsChannel.broadcast_refresh_to("predictions")
    end
  end
end
