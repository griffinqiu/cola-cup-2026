module Broadcasts
  # A pick change (or the lock) moves the pools shown on the predictions page;
  # refresh it for every viewer via Turbo morphing, the same way SettlementJob
  # refreshes match pages. Args are accepted but unused — any change refreshes
  # the whole page.
  class OutrightJob < ApplicationJob
    include Renderable
    queue_as :default

    def perform(*)
      broadcast_refresh_each_locale("predictions")
    end
  end
end
