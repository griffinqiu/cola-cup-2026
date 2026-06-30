require "rails_helper"

RSpec.describe Openfootball::ScheduleImport do
  def import(matches, teams: [])
    allow(HttpJson).to receive(:get).with(described_class::TEAMS_URL).and_return(teams)
    allow(HttpJson).to receive(:get).with(described_class::SCHEDULE_URL).and_return("matches" => matches)
    described_class.run(source: :network)
  end

  def ko_payload(num, round, team1, team2)
    { "num" => num, "round" => round, "team1" => team1, "team2" => team2,
      "ground" => "Stadium", "date" => "2026-07-04", "time" => "13:00 UTC-6" }
  end

  # Openfootball is the fallback for knockout matchups, not the authority: a slot
  # already resolved locally (KnockoutResolver) must survive an import where the
  # upstream JSON still carries the placeholder.
  describe "knockout slot preservation" do
    it "keeps a locally-resolved team id when the upstream slot is still a placeholder" do
      spain = create(:team, name: "Spain")
      slot = create(:match, stage: "r16", group_name: nil, external_key: "m:89",
        home_team: spain, home_label: nil, away_team: nil, away_label: "W77")

      import([ ko_payload(89, "Round of 16", "W74", "W77") ])

      slot.reload
      expect(slot.home_team_id).to eq(spain.id)
      expect(slot.home_label).to be_nil
      expect(slot.away_team_id).to be_nil
      expect(slot.away_label).to eq("W77")
    end

    it "fills a slot once the upstream names a real team" do
      spain = create(:team, name: "Spain")
      croatia = create(:team, name: "Croatia")
      slot = create(:match, stage: "r16", group_name: nil, external_key: "m:89",
        home_team: nil, home_label: "W74", away_team: nil, away_label: "W77")

      import([ ko_payload(89, "Round of 16", "Spain", "Croatia") ])

      slot.reload
      expect(slot.home_team_id).to eq(spain.id)
      expect(slot.away_team_id).to eq(croatia.id)
      expect(slot.home_label).to be_nil
      expect(slot.away_label).to be_nil
    end
  end

  describe "penalty shootout score" do
    it "fills pen_home/pen_away from openfootball's score.p ([home, away])" do
      germany = create(:team, name: "Germany")
      paraguay = create(:team, name: "Paraguay")
      slot = create(:match, stage: "r32", group_name: nil, external_key: "m:74",
        home_team: germany, home_label: nil, away_team: paraguay, away_label: nil)

      payload = ko_payload(74, "Round of 32", "Germany", "Paraguay")
        .merge("score" => { "ft" => [ 1, 1 ], "p" => [ 3, 4 ] })
      import([ payload ])

      slot.reload
      expect(slot.pen_home).to eq(3)
      expect(slot.pen_away).to eq(4)
    end

    it "leaves pen scores nil for a match decided without a shootout" do
      spain = create(:team, name: "Spain")
      croatia = create(:team, name: "Croatia")
      slot = create(:match, stage: "r32", group_name: nil, external_key: "m:83",
        home_team: spain, home_label: nil, away_team: croatia, away_label: nil)

      import([ ko_payload(83, "Round of 32", "Spain", "Croatia").merge("score" => { "ft" => [ 2, 1 ] }) ])

      slot.reload
      expect(slot.pen_home).to be_nil
      expect(slot.pen_away).to be_nil
    end
  end
end
