require "rails_helper"

RSpec.describe Champion do
  let(:home) { create(:team) }
  let(:away) { create(:team) }
  let(:bettor) { create(:user) }
  let(:other) { create(:user) }

  def champ_pick(user, team, side)
    create(:outright_pick, user: user, market: "champion",
           subject_key: "team:#{team.id}", subject_label: team.name, team_id: team.id, pick: side)
  end

  describe ".settle_for_match" do
    it "settles the eliminated team's pool as 'no' on a knockout result" do
      match = create(:match, :knockout, home_team: home, away_team: away,
                     result: "home", result_at: Time.current)
      champ_pick(bettor, away, "yes")
      champ_pick(other, away, "no")

      described_class.settle_for_match(match)

      entry = OutrightLedgerEntry.find_by(user: bettor, subject_key: "team:#{away.id}")
      expect(entry.outcome).to eq("lost")
      expect(entry.delta).to eq(-1.0)
      expect(entry.source_match_id).to eq(match.id)
    end

    it "settles a round-of-32 loser's pool as 'no' (the market opens at the round of 32)" do
      match = create(:match, home_team: home, away_team: away, stage: "r32",
                     group_name: nil, result: "home", result_at: Time.current)
      champ_pick(bettor, away, "yes")
      champ_pick(other, away, "no")

      described_class.settle_for_match(match)

      entry = OutrightLedgerEntry.find_by(user: bettor, subject_key: "team:#{away.id}")
      expect(entry.outcome).to eq("lost")
      expect(entry.delta).to eq(-1.0)
    end

    it "settles the final winner's pool as 'yes' (champion)" do
      match = create(:match, home_team: home, away_team: away, stage: "final",
                     group_name: nil, result: "home", result_at: Time.current)
      champ_pick(bettor, home, "yes")
      champ_pick(other, home, "no")

      described_class.settle_for_match(match)

      entry = OutrightLedgerEntry.find_by(user: bettor, subject_key: "team:#{home.id}")
      expect(entry.outcome).to eq("won_title")
      expect(entry.delta).to eq(1.0)
    end

    it "settles both sides of the final — loser out, winner champion" do
      match = create(:match, home_team: home, away_team: away, stage: "final",
                     group_name: nil, result: "home", result_at: Time.current)
      champ_pick(bettor, home, "yes")
      champ_pick(other, home, "no")
      champ_pick(bettor, away, "yes")
      champ_pick(other, away, "no")

      described_class.settle_for_match(match)

      expect(OutrightLedgerEntry.find_by(subject_key: "team:#{home.id}", user: bettor).outcome).to eq("won_title")
      expect(OutrightLedgerEntry.find_by(subject_key: "team:#{away.id}", user: bettor).outcome).to eq("lost")
    end

    it "ignores group-stage matches" do
      match = create(:match, home_team: home, away_team: away, stage: "group", result: "home")
      champ_pick(bettor, away, "yes")

      described_class.settle_for_match(match)

      expect(OutrightLedgerEntry.count).to eq(0)
    end

    it "ignores the third-place match (both teams already settled at the semis)" do
      match = create(:match, home_team: home, away_team: away, stage: "third",
                     group_name: nil, result: "home", result_at: Time.current)
      champ_pick(bettor, away, "yes")

      described_class.settle_for_match(match)

      expect(OutrightLedgerEntry.count).to eq(0)
    end
  end
end
