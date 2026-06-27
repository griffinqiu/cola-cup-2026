require "rails_helper"

RSpec.describe GoldenBoot do
  let(:strong) { create(:team) }
  let(:weak) { create(:team) }

  def score(team, player, count, penalty: false)
    match = create(:match, home_team: team, away_team: create(:team))
    count.times { create(:goal, match: match, team: team, player_name: player, penalty: penalty) }
  end

  def candidate(team, player, goals_at_lock)
    create(:outright_candidate, market: "golden_boot",
           subject_key: "scorer:#{team.id}:#{player}", subject_label: player,
           team_id: team.id, meta: { "team_id" => team.id, "goals_at_lock" => goals_at_lock })
  end

  def gb_pick(user, team, player, side)
    create(:outright_pick, user: user, market: "golden_boot",
           subject_key: "scorer:#{team.id}:#{player}", subject_label: player, team_id: team.id, pick: side)
  end

  def eliminate(team)
    create(:match, :knockout, home_team: create(:team), away_team: team,
           result: "home", result_at: Time.current)
  end

  describe ".sweep!" do
    let(:backer) { create(:user) }
    let(:fader) { create(:user) }

    it "early-settles 'no' for an eliminated candidate trailing the leader" do
      score(strong, "Leader", 5)
      score(weak, "Trailer", 2)
      candidate(strong, "Leader", 5)
      candidate(weak, "Trailer", 2)
      gb_pick(backer, weak, "Trailer", "yes")
      gb_pick(fader, weak, "Trailer", "no")
      eliminate(weak)

      described_class.sweep!

      trailer = OutrightLedgerEntry.find_by(subject_key: "scorer:#{weak.id}:Trailer", user: backer)
      expect(trailer.outcome).to eq("lost")
      expect(trailer.delta).to eq(-1.0)
      expect(OutrightLedgerEntry.where(subject_key: "scorer:#{strong.id}:Leader")).to be_empty
    end

    it "leaves an eliminated candidate tied for the lead for the final reveal" do
      score(strong, "Leader", 5)
      score(weak, "Tied", 5)
      candidate(strong, "Leader", 5)
      candidate(weak, "Tied", 5)
      gb_pick(backer, weak, "Tied", "yes")
      gb_pick(fader, weak, "Tied", "no")
      eliminate(weak)

      described_class.sweep!

      expect(OutrightLedgerEntry.where(subject_key: "scorer:#{weak.id}:Tied")).to be_empty
    end

    it "leaves a trailing candidate whose team is still alive" do
      score(strong, "Leader", 5)
      score(weak, "Trailer", 2)
      candidate(strong, "Leader", 5)
      candidate(weak, "Trailer", 2)
      gb_pick(backer, weak, "Trailer", "yes")
      gb_pick(fader, weak, "Trailer", "no")
      # weak NOT eliminated

      described_class.sweep!

      expect(OutrightLedgerEntry.where(subject_key: "scorer:#{weak.id}:Trailer")).to be_empty
    end

    it "no-ops before the field is locked (no candidates)" do
      score(strong, "Leader", 5)
      eliminate(weak)
      expect { described_class.sweep! }.not_to change(OutrightLedgerEntry, :count)
    end
  end

  describe ".open_final!" do
    let(:backer) { create(:user) }
    let(:fader) { create(:user) }

    it "settles the top scorer 'yes' and everyone else 'no'" do
      score(strong, "Leader", 5)
      score(weak, "Trailer", 4)
      candidate(strong, "Leader", 5)
      candidate(weak, "Trailer", 4)
      gb_pick(backer, strong, "Leader", "yes")
      gb_pick(fader, strong, "Leader", "no")
      gb_pick(backer, weak, "Trailer", "yes")
      gb_pick(fader, weak, "Trailer", "no")
      admin = create(:user)

      described_class.open_final!(settled_by: admin)

      leader = OutrightLedgerEntry.find_by(subject_key: "scorer:#{strong.id}:Leader", user: backer)
      trailer = OutrightLedgerEntry.find_by(subject_key: "scorer:#{weak.id}:Trailer", user: backer)
      expect(leader.outcome).to eq("won_title")
      expect(leader.delta).to eq(1.0)
      expect(leader.settled_by_id).to eq(admin.id)
      expect(trailer.outcome).to eq("lost")
      expect(trailer.delta).to eq(-1.0)
    end
  end

  describe ".can_open_final?" do
    it "is false when the final has no result yet" do
      create(:match, :knockout, stage: "final", result: nil)
      expect(described_class.can_open_final?).to be(false)
    end

    it "is false when the final has a result but its goals aren't fully synced" do
      final = create(:match, :knockout, stage: "final",
                     result: "home", home_score: 2, away_score: 1, result_at: Time.current)
      create(:goal, match: final, team: final.home_team) # only 1 of 3 goals imported

      expect(described_class.can_open_final?).to be(false)
    end

    it "is true once the goal events reconcile with the final score" do
      final = create(:match, :knockout, stage: "final",
                     result: "home", home_score: 2, away_score: 1, result_at: Time.current)
      2.times { create(:goal, match: final, team: final.home_team) }
      create(:goal, match: final, team: final.away_team)

      expect(described_class.can_open_final?).to be(true)
    end

    it "opens a penalty-shootout final immediately (draw score, shootout goals never hit the board)" do
      final = create(:match, :knockout, stage: "final",
                     result: "home", home_score: 1, away_score: 1, result_at: Time.current)
      create(:goal, match: final, team: final.home_team)
      create(:goal, match: final, team: final.away_team)

      expect(described_class.can_open_final?).to be(true)
    end
  end
end
