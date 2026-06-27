class OutrightCandidate < ApplicationRecord
  # Snapshot of a market's bettable subjects, frozen at lock time. Before lock
  # the page computes candidates live (Champion.candidates / GoldenBoot.candidates);
  # once these rows exist the market is "locked" and everything reads from here.
  belongs_to :team, optional: true

  scope :for_market, ->(market) { where(market: market) }
end
