# Freezes each outright candidate as its own deadline (1h before that team's
# round-of-16 match) passes: snapshots the champion market odds and purges its
# one-sided pool. Per-team, not a single global cutoff. Idempotent — a frozen
# subject (its OutrightCandidate row exists) is skipped. Runs every 10 minutes.
class OutrightLockJob < ApplicationJob
  queue_as :default

  def perform
    return unless Champion.available?

    now = Time.current
    champion_probs = Polymarket::ChampionOdds.probabilities
    deadlines = Champion.deadlines_by_team
    froze = false

    (Champion.candidate_subjects + GoldenBoot.candidate_subjects).each do |subject|
      deadline = deadlines[subject.team_id]
      next if deadline.nil? || now < deadline
      next if OutrightCandidate.exists?(market: subject.market, subject_key: subject.subject_key)

      freeze_subject(subject, now, champion_probs)
      froze = true
    end

    Broadcasts::OutrightJob.perform_later if froze
  end

  private

  def freeze_subject(subject, now, champion_probs)
    meta = subject.meta || {}
    if subject.market == Champion::MARKET && (prob = champion_probs[subject.team_id])
      meta = meta.merge("prob" => prob)
    end
    OutrightCandidate.create!(
      market: subject.market, subject_key: subject.subject_key,
      subject_label: subject.subject_label, team_id: subject.team_id, meta: meta, frozen_at: now
    )
    purge_if_one_sided(subject.market, subject.subject_key)
  end

  # A subject nobody bet against can only push, so returning the stakes (deleting
  # the picks, no ledger ever written) keeps that cola untouched.
  def purge_if_one_sided(market, subject_key)
    sides = OutrightPick.where(market: market, subject_key: subject_key).distinct.pluck(:pick)
    OutrightPick.where(market: market, subject_key: subject_key).delete_all if sides.size < 2
  end
end
