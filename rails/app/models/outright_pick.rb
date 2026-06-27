class OutrightPick < ApplicationRecord
  MARKETS = %w[champion golden_boot].freeze
  PICKS = %w[yes no].freeze
  # Players pick how many bottles to stake; pari-mutuel settlement weights each
  # side by its total stake, so a heavier bet wins (or loses) proportionally more.
  STAKE_OPTIONS = [ 1.0, 2.0, 3.0 ].freeze
  DEFAULT_STAKE = 1.0

  # Stake sums per side (yes/no) plus the distinct-picker count, mirroring
  # Vote::Tally — drives the pool display and the "N 人" label.
  Tally = Struct.new(:yes, :no, :stake_total, :voters, keyword_init: true)

  belongs_to :user
  belongs_to :team, optional: true

  validates :market, inclusion: { in: MARKETS }
  validates :pick, inclusion: { in: PICKS }
  validates :subject_key, presence: true
  validates :subject_label, presence: true
  validates :stake, inclusion: { in: STAKE_OPTIONS }
  validates :user_id, uniqueness: { scope: [ :market, :subject_key ] }

  # Soft-deleted users drop out of tallies and settlement, exactly like Vote.
  scope :active, -> { joins(:user).where(users: { deleted_at: nil }) }
  scope :for_market, ->(market) { where(market: market) }

  # A pick change moves the pool shown on the candidate card.
  after_commit :broadcast_change

  def self.empty_tally
    Tally.new(yes: 0.0, no: 0.0, stake_total: 0.0, voters: 0)
  end

  # Yes/no stake + picker tally for one subject (active pickers only).
  def self.tally_for(market, subject_key)
    fill_tally(empty_tally, active.where(market: market, subject_key: subject_key)
      .group(:pick)
      .pluck(:pick, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(stake), 0)")))
  end

  # Every subject's tally for a market in one query, keyed by subject_key.
  def self.tallies_for(market)
    rows = active.where(market: market)
      .group(:subject_key, :pick)
      .pluck(:subject_key, :pick, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(stake), 0)"))
    rows.each_with_object({}) do |(subject_key, pick, count, stake_sum), map|
      tally = map[subject_key] ||= empty_tally
      apply_tally_row(tally, pick, count, stake_sum)
    end
  end

  # Per-subject roster, oldest edit first, profiles preloaded — for settlement.
  def self.detailed_for(market, subject_key)
    active.where(market: market, subject_key: subject_key).includes(:user).order(:updated_at)
  end

  def self.fill_tally(tally, grouped)
    grouped.each { |pick, count, stake_sum| apply_tally_row(tally, pick, count, stake_sum) }
    tally
  end
  private_class_method :fill_tally

  def self.apply_tally_row(tally, pick, count, stake_sum)
    tally[pick] = stake_sum.to_f
    tally.stake_total += stake_sum.to_f
    tally.voters += count
  end
  private_class_method :apply_tally_row

  private

  def broadcast_change
    Broadcasts::OutrightJob.perform_later(market, subject_key)
  end
end
