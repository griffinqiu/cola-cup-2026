require "rails_helper"

# Outright winnings are real cola: they must flow into the balance and the
# leaderboard total (but not the bets/wins accuracy boards).
RSpec.describe "outright balance integration" do
  let(:user) { create(:user) }

  it "includes outright ledger delta in net_balance" do
    create(:ledger_entry, user: user, delta: 2.0)
    create(:outright_ledger_entry, user: user, delta: 3.0, subject_key: "team:1")
    create(:redemption, user: user, cost: 1.0)

    expect(user.net_balance).to be_within(1e-9).of(4.0)
  end

  it "counts outright delta in the leaderboard total but not in bets/wins" do
    create(:ledger_entry, user: user, delta: 2.0)
    create(:outright_ledger_entry, user: user, delta: 3.0, subject_key: "team:1")

    entry = User.leaderboard.find { |row| row.id == user.id }
    expect(entry.total).to be_within(1e-9).of(5.0)
    expect(entry.bets).to eq(1)
    expect(entry.wins).to eq(1)
  end
end
