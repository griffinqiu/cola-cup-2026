require "rails_helper"

RSpec.describe OutrightSettlement do
  def pick(user, side, stake: 1.0, subject_key: "team:1")
    create(:outright_pick, user: user, market: "champion",
           subject_key: subject_key, subject_label: "X", pick: side, stake: stake)
  end

  def settle(subject_key: "team:1", winning_pick: "no", outcome: "lost", **opts)
    described_class.settle!(market: "champion", subject_key: subject_key, subject_label: "X",
                            team_id: nil, winning_pick: winning_pick, outcome: outcome, **opts)
  end

  let(:a) { create(:user) }
  let(:b) { create(:user) }
  let(:c) { create(:user) }

  it "transfers the losers' stake to the winners and stays zero-sum" do
    pick(a, "yes")
    pick(b, "no")
    pick(c, "no")

    settle(winning_pick: "no")

    entries = OutrightLedgerEntry.where(subject_key: "team:1")
    expect(entries.sum(&:delta)).to be_within(1e-9).of(0.0)
    expect(entries.find_by(user: a).delta).to eq(-1.0)
    expect(entries.find_by(user: b).delta).to be_within(1e-9).of(0.5)
    expect(entries.find_by(user: b).won).to be(true)
  end

  it "weights payouts by stake — heavier bets win or lose proportionally more" do
    # 否 pool stake = 3 + 1 = 4 (winners); 对 pool stake = 2 (the only loser).
    pick(a, "no", stake: 3.0)
    pick(b, "no", stake: 1.0)
    pick(c, "yes", stake: 2.0)

    settle(winning_pick: "no")

    entries = OutrightLedgerEntry.where(subject_key: "team:1")
    expect(entries.find_by(user: a).delta).to be_within(1e-9).of(1.5) # 3/4 of the 2-bottle pool
    expect(entries.find_by(user: b).delta).to be_within(1e-9).of(0.5) # 1/4 of it
    expect(entries.find_by(user: c).delta).to eq(-2.0)                # forfeits its 2 bottles
    expect(entries.sum(&:delta)).to be_within(1e-9).of(0.0)
  end

  it "refunds without eating cola when the pool has no opposing side (push)" do
    pick(a, "yes")
    pick(b, "yes")

    settle(winning_pick: "no")

    entries = OutrightLedgerEntry.where(subject_key: "team:1")
    expect(entries.map(&:delta)).to all(eq(0.0))
    expect(entries.sum(&:delta)).to be_within(1e-9).of(0.0)
  end

  it "is idempotent — a subject settles exactly once" do
    pick(a, "yes")
    pick(b, "no")

    expect(settle).to be(true)
    expect(settle).to be(false)
    expect(OutrightLedgerEntry.where(subject_key: "team:1").count).to eq(2)
  end

  it "no-ops when the subject has no picks" do
    expect(settle(subject_key: "team:9")).to be(false)
    expect(OutrightLedgerEntry.count).to eq(0)
  end

  it "records who settled and the outcome" do
    admin = create(:user)
    pick(a, "yes")
    pick(b, "no")

    settle(winning_pick: "yes", outcome: "won_title", settled_by: admin)

    entry = OutrightLedgerEntry.find_by(user: a)
    expect(entry.outcome).to eq("won_title")
    expect(entry.won).to be(true)
    expect(entry.settled_by_id).to eq(admin.id)
  end
end
