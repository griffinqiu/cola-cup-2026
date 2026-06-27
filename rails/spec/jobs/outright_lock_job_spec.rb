require "rails_helper"

RSpec.describe OutrightLockJob do
  # A full 8-match round-of-16 field. The first match kicks off soon (its two
  # teams are past the 1h deadline); the rest are days away.
  def r16_field(past_a:, past_b:)
    create(:match, stage: "r16", group_name: nil, kickoff_at: 30.minutes.ago,
           home_team: past_a, away_team: past_b)
    7.times { create(:match, stage: "r16", group_name: nil, kickoff_at: 5.days.from_now) }
  end

  def champ_pick(user, team, side)
    create(:outright_pick, user: user, market: "champion", subject_key: "team:#{team.id}",
           subject_label: team.name, team_id: team.id, pick: side)
  end

  it "freezes a team past its own deadline and purges its one-sided pool" do
    a = create(:team)
    b = create(:team)
    r16_field(past_a: a, past_b: b)
    u1 = create(:user)
    u2 = create(:user)
    champ_pick(u1, a, "yes")
    champ_pick(u2, a, "no")  # two-sided on A → kept
    champ_pick(u1, b, "yes") # one-sided on B → purged

    described_class.new.perform

    expect(OutrightPick.where(subject_key: "team:#{a.id}").count).to eq(2)
    expect(OutrightPick.where(subject_key: "team:#{b.id}").count).to eq(0)
    expect(OutrightCandidate.where(market: "champion", subject_key: "team:#{a.id}")).to be_present
  end

  it "leaves a team whose deadline hasn't passed" do
    a = create(:team)
    b = create(:team)
    create(:match, stage: "r16", group_name: nil, kickoff_at: 5.days.from_now, home_team: a, away_team: b)
    7.times { create(:match, stage: "r16", group_name: nil, kickoff_at: 5.days.from_now) }
    champ_pick(create(:user), a, "yes")

    described_class.new.perform

    expect(OutrightPick.where(subject_key: "team:#{a.id}").count).to eq(1)
    expect(OutrightCandidate.where(subject_key: "team:#{a.id}")).to be_empty
  end

  it "snapshots the champion market odds into the frozen candidate (odds freeze at lock)" do
    a = create(:team)
    b = create(:team)
    r16_field(past_a: a, past_b: b)
    allow(Polymarket::ChampionOdds).to receive(:probabilities).and_return(a.id => 0.42)
    champ_pick(create(:user), a, "yes")
    champ_pick(create(:user), a, "no")

    described_class.new.perform

    candidate = OutrightCandidate.find_by(market: "champion", subject_key: "team:#{a.id}")
    expect(candidate.meta["prob"]).to eq(0.42)
  end

  it "no-ops when no round-of-16 team is known yet" do
    create(:match, stage: "group", group_name: "A") # no r16 teams at all
    expect { described_class.new.perform }.not_to change(OutrightCandidate, :count)
  end
end
