require "rails_helper"

RSpec.describe MatchesHelper, type: :helper do
  def tally(home:, draw:, away:)
    Vote::Tally.new(
      home: home, draw: draw, away: away,
      stake_total: home + draw + away, voters: 0
    )
  end

  describe "#preview_odds_by_pick" do
    let(:match) { build_stubbed(:match, stage: "group") } # stake 1.0, allows draw

    it "lets a new voter on an unbacked side win the existing pool" do
      # 葡萄牙 (home) has one 1-bottle vote; the viewer has not voted yet.
      odds = helper.preview_odds_by_pick(match, tally(home: 1.0, draw: 0.0, away: 0.0), nil)

      # Pick 平 (draw): pool = my 1, total = their 1 + my 1 = 2 => 2.0 => win 1 瓶.
      expect(odds["draw"]).to be_within(1e-9).of(2.0)
      # Pick 葡萄牙: I'd just join the only backed side — no losers, win nothing.
      expect(odds["home"]).to be_within(1e-9).of(1.0)
    end

    it "moves the viewer's existing stake onto the previewed side (no double count)" do
      # home=2 (includes my 1 bottle), away=1; I currently picked home.
      odds = helper.preview_odds_by_pick(match, tally(home: 2.0, draw: 0.0, away: 1.0), "home")

      # Staying on home: total 3 / home 2 = 1.5 (unchanged raw crowd odds).
      expect(odds["home"]).to be_within(1e-9).of(1.5)
      # Switching to away moves my stake (home->1, away->2); total stays 3 =>
      # 3/2 = 1.5, not the misleading raw 3/1 = 3 that ignores the move.
      expect(odds["away"]).to be_within(1e-9).of(1.5)
    end

    it "omits draw for knockout stages" do
      ko = build_stubbed(:match, :knockout)
      odds = helper.preview_odds_by_pick(ko, tally(home: 2.0, draw: 0.0, away: 0.0), nil)

      expect(odds.keys).to contain_exactly("home", "away")
    end
  end

  describe "#preview_pool" do
    let(:match) { build_stubbed(:match, stage: "group") }

    it "returns the full crowd pool when the viewer has not voted" do
      pool = helper.preview_pool(match, tally(home: 2.0, draw: 1.0, away: 0.0), nil)
      expect(pool[:others_total]).to eq(3.0)
      expect(pool[:by_pick]).to eq("home" => 2.0, "draw" => 1.0, "away" => 0.0)
    end

    it "removes the viewer's own stake from the total and their backed side" do
      vote = build_stubbed(:vote, pick: "home", stake: 2.0)
      pool = helper.preview_pool(match, tally(home: 2.0, draw: 1.0, away: 0.0), vote)
      expect(pool[:others_total]).to eq(1.0)
      expect(pool[:by_pick]["home"]).to eq(0.0)
      expect(pool[:by_pick]["draw"]).to eq(1.0)
    end
  end

  describe "#pick_label_font_px" do
    it "keeps short labels at the max size" do
      expect(helper.pick_label_font_px("乌拉圭")).to eq(20)
      expect(helper.pick_label_font_px("平局")).to eq(20)
    end

    it "shrinks long names so they stay on one line" do
      expect(helper.pick_label_font_px("沙特阿拉伯")).to be < 20    # 5 chars
      expect(helper.pick_label_font_px("乌兹别克斯坦")).to be < 16  # 6 chars
    end

    it "never shrinks past the minimum size" do
      expect(helper.pick_label_font_px("波斯尼亚和黑塞哥维那")).to eq(11) # 10 chars
    end
  end

  describe "score tokens with a penalty shootout" do
    let(:label) { I18n.t("matches.penalty_score") }

    it "shows just the score when there was no shootout" do
      match = build_stubbed(:match, :knockout, :with_result, home_score: 2, away_score: 1)
      expect(helper.match_score_token(match)).to eq("2–1")
    end

    it "appends the shootout digits to the card score token" do
      match = build_stubbed(:match, :knockout, :with_result, home_score: 1, away_score: 1, pen_home: 2, pen_away: 3)
      expect(helper.match_score_token(match)).to eq("1–1（#{label} 2:3）")
    end

    it "appends the shootout digits to the settled detail score token" do
      match = build_stubbed(:match, :knockout, :settled, home_score: 1, away_score: 1, pen_home: 3, pen_away: 4)
      expect(helper.detail_score_token(match)).to eq("1–1（#{label} 3:4）")
    end

    it "shows VS before any score is recorded" do
      match = build_stubbed(:match, :knockout, home_score: nil, away_score: nil)
      expect(helper.match_score_token(match)).to eq("VS")
    end
  end
end
