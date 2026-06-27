class FetchOddsJob < ApplicationJob
  queue_as :default

  def perform
    result = Polymarket::Sync.run
    Rails.logger.info(
      "[FetchOddsJob] events=#{result[:events]} matched=#{result[:matched]} unmatched=#{result[:unmatched]}"
    )

    # Refresh the standalone champion-winner odds (display-only) alongside the
    # per-match moneyline sync. A failure here must not fail the moneyline run.
    begin
      probs = Polymarket::ChampionOdds.refresh!
      Rails.logger.info("[FetchOddsJob] champion odds teams=#{probs.size}")
    rescue StandardError => e
      Rails.logger.warn("[FetchOddsJob] champion odds skipped: #{e.class}: #{e.message}")
    end
  end
end
