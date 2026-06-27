class Redemption < ApplicationRecord
  RedeemError = Class.new(StandardError)

  belongs_to :user

  validates :drink, presence: true
  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_cost, :cost, presence: true

  # A redemption shifts the 已兑 column on the leaderboard (rank itself unchanged).
  after_commit :broadcast_leaderboard_change, on: :create

  def broadcast_leaderboard_change
    Broadcasts::LeaderboardJob.perform_later
  end

  # Redeem `qty` bottles of a drink. The balance is intentionally not checked:
  # anyone can redeem regardless of credits, and the balance is allowed to go
  # negative (losers drink too; the season settles up at the end). Raises
  # RedeemError (Chinese message) on an unknown drink or a non-positive quantity.
  def self.redeem!(user:, drink_key:, qty:)
    drink = Drink.find(drink_key)
    raise RedeemError, I18n.t("errors.redemption.unknown_drink") unless drink
    raise RedeemError, I18n.t("errors.redemption.invalid_quantity") unless qty.is_a?(Integer) && qty >= 1

    cost = drink.cost * qty
    create!(user: user, drink: drink.key, qty: qty, unit_cost: drink.cost, cost: cost)
  end
end
