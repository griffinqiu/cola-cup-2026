require "rails_helper"

RSpec.describe OutrightLockJob do
  # A round-of-32 match makes `a` and `b` champion candidates; a quarter-final
  # match slots them into a QF whose kickoff drives their per-team lock (1h before).
  def r32_teams(a, b)
    create(:match, stage: "r32", group_name: nil, kickoff_at: 6.days.from_now, home_team: a, away_team: b)
  end

  def qf_match(a, b, at)
    create(:match, stage: "qf", group_name: nil, kickoff_at: at, home_team: a, away_team: b)
  end

  def champ_pick(user, team, side)
    create(:outright_pick, user: user, market: "champion", subject_key: "team:#{team.id}",
           subject_label: team.name, team_id: team.id, pick: side)
  end

  it "freezes a team past its own quarter-final deadline and purges its one-sided pool" do
    a = create(:team)
    b = create(:team)
    r32_teams(a, b)
    qf_match(a, b, 30.minutes.ago) # deadline (1h before) is well past
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

  it "leaves a team whose quarter-final deadline hasn't passed" do
    a = create(:team)
    b = create(:team)
    r32_teams(a, b)
    qf_match(a, b, 5.days.from_now)
    champ_pick(create(:user), a, "yes")

    described_class.new.perform

    expect(OutrightPick.where(subject_key: "team:#{a.id}").count).to eq(1)
    expect(OutrightCandidate.where(subject_key: "team:#{a.id}")).to be_empty
  end

  it "leaves an alive team not yet slotted into a quarter-final (no deadline, stays open)" do
    a = create(:team)
    b = create(:team)
    r32_teams(a, b) # in the round of 32, but no quarter-final scheduled for them yet
    champ_pick(create(:user), a, "yes") # one-sided but still open → not purged

    described_class.new.perform

    expect(OutrightPick.where(subject_key: "team:#{a.id}").count).to eq(1)
    expect(OutrightCandidate.where(subject_key: "team:#{a.id}")).to be_empty
  end

  it "snapshots the champion market odds into the frozen candidate (odds freeze at lock)" do
    a = create(:team)
    b = create(:team)
    r32_teams(a, b)
    qf_match(a, b, 30.minutes.ago)
    allow(Polymarket::ChampionOdds).to receive(:probabilities).and_return(a.id => 0.42)
    champ_pick(create(:user), a, "yes")
    champ_pick(create(:user), a, "no")

    described_class.new.perform

    candidate = OutrightCandidate.find_by(market: "champion", subject_key: "team:#{a.id}")
    expect(candidate.meta["prob"]).to eq(0.42)
  end

  it "skips a team whose pool already settled (eliminated before its quarter-final)" do
    a = create(:team)
    b = create(:team)
    r32_teams(a, b)
    qf_match(a, b, 30.minutes.ago)
    create(:outright_ledger_entry, market: "champion", subject_key: "team:#{a.id}",
           subject_label: a.name, team_id: a.id, outcome: "lost", won: false, delta: -1.0)
    champ_pick(create(:user), a, "yes") # lone leftover pick must not be re-frozen or purged

    described_class.new.perform

    expect(OutrightCandidate.where(subject_key: "team:#{a.id}")).to be_empty
    expect(OutrightPick.where(subject_key: "team:#{a.id}").count).to eq(1)
  end

  it "no-ops when no round-of-32 team is known yet" do
    create(:match, stage: "group", group_name: "A") # no knockout teams at all
    expect { described_class.new.perform }.not_to change(OutrightCandidate, :count)
  end
end
