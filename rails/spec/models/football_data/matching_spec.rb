require "rails_helper"

RSpec.describe FootballData::Matching do
  # Minimal host exposing the private helper, mirroring how LiveScoresSync mixes it in.
  let(:harness) do
    Class.new do
      include FootballData::Matching
      public :derive_result
    end.new
  end

  def payload(winner:, full_time: nil)
    score = { "winner" => winner }
    score["fullTime"] = full_time if full_time
    { "score" => score }
  end

  describe "#derive_result" do
    context "group games (knockout: false)" do
      it "maps football-data's winner onto our home/away" do
        expect(harness.derive_result(payload(winner: "HOME_TEAM"), true)).to eq("home")
        expect(harness.derive_result(payload(winner: "AWAY_TEAM"), true)).to eq("away")
        expect(harness.derive_result(payload(winner: "AWAY_TEAM"), false)).to eq("home")
      end

      it "returns draw for a DRAW winner or a level full-time score" do
        expect(harness.derive_result(payload(winner: "DRAW"), true)).to eq("draw")
        expect(
          harness.derive_result(payload(winner: nil, full_time: { "home" => 1, "away" => 1 }), true)
        ).to eq("draw")
      end
    end

    context "knockout games (knockout: true)" do
      it "still resolves a decisive winner" do
        expect(harness.derive_result(payload(winner: "AWAY_TEAM"), true, knockout: true)).to eq("away")
        expect(
          harness.derive_result(payload(winner: nil, full_time: { "home" => 2, "away" => 1 }), true, knockout: true)
        ).to eq("home")
      end

      it "returns nil for a DRAW winner — wait for the shootout winner, never freeze a draw" do
        expect(harness.derive_result(payload(winner: "DRAW"), true, knockout: true)).to be_nil
      end

      it "returns nil for a level full-time score with no winner yet" do
        expect(
          harness.derive_result(payload(winner: nil, full_time: { "home" => 1, "away" => 1 }), true, knockout: true)
        ).to be_nil
      end
    end
  end
end
