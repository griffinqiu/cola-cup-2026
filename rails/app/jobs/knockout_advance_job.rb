# Propagates decided knockout outcomes into the next round's matchups. Scheduled
# after every knockout result is recorded (Match#record_result!), and re-run by the
# periodic ImportScheduleJob as a backstop. The match id is accepted for a uniform
# schedule(match) signature but unused — the resolver always sweeps the whole
# bracket, which is idempotent.
class KnockoutAdvanceJob < ApplicationJob
  queue_as :default

  def self.schedule(match)
    perform_later(match.id)
  end

  def perform(_match_id = nil)
    resolved = KnockoutResolver.run
    Rails.logger.info("[KnockoutAdvanceJob] resolved=#{resolved}") if resolved.positive?
  end
end
