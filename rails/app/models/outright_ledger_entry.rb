class OutrightLedgerEntry < ApplicationRecord
  # The frozen settlement of one outright pick. Keyed unique by
  # (user_id, market, subject_key), so OutrightSettlement.settle! is idempotent
  # via insert_all — a subject settles exactly once.
  OUTCOMES = %w[won_title lost].freeze

  belongs_to :user
  belongs_to :team, optional: true
  belongs_to :source_match, class_name: "Match", optional: true
  belongs_to :settled_by, class_name: "User", optional: true

  scope :for_market, ->(market) { where(market: market) }
end
