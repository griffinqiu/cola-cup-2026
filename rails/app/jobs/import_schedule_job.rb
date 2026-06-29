class ImportScheduleJob < ApplicationJob
  queue_as :default

  def perform
    result = Openfootball::ScheduleImport.run(source: :network)
    Rails.logger.info("[ImportScheduleJob] teams=#{result[:teams]} matches=#{result[:matches]}")

    # Now that goal data is fresh, settle any golden-boot candidate that can no
    # longer catch the leader (its team is out and it trails). No-ops until lock.
    # Guarded so a settlement hiccup never fails the (critical) schedule import.
    begin
      GoldenBoot.sweep!
    rescue StandardError => e
      Rails.logger.warn("[ImportScheduleJob] golden boot sweep skipped: #{e.class}: #{e.message}")
    end

    # Backstop the per-result KnockoutAdvanceJob: fill any knockout matchup now
    # decidable from recorded results (and correct slots upstream just backfilled).
    begin
      resolved = KnockoutResolver.run
      Rails.logger.info("[ImportScheduleJob] knockout resolved=#{resolved}") if resolved.positive?
    rescue StandardError => e
      Rails.logger.warn("[ImportScheduleJob] knockout resolve skipped: #{e.class}: #{e.message}")
    end
  end
end
