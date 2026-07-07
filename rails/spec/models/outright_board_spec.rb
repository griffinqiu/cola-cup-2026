require "rails_helper"

RSpec.describe OutrightBoard do
  # Champion candidates are the knockout (round-of-32) teams; build a field and
  # pick three known teams to assert ordering against.
  def r32_field
    8.times.map { create(:match, stage: "r32", group_name: nil, kickoff_at: 5.days.from_now) }
  end

  def settle_lost(team)
    create(:outright_ledger_entry, market: "champion", subject_key: "team:#{team.id}",
           subject_label: team.name, team_id: team.id, outcome: "lost", won: false, delta: -1.0)
  end

  it "orders champion by Polymarket probability and sinks eliminated to the bottom" do
    matches = r32_field
    top = matches[0].home_team
    mid = matches[0].away_team
    out = matches[1].home_team

    allow(Polymarket::ChampionOdds).to receive(:probabilities)
      .and_return(top.id => 0.30, mid.id => 0.10, out.id => 0.50)
    settle_lost(out) # eliminated despite the highest market prob -> still goes last

    keys = OutrightBoard.new("champion", nil).rows.map { |row| row.subject.team_id }

    expect(keys.index(top.id)).to be < keys.index(mid.id)         # 0.30 before 0.10
    expect(keys.last).to eq(out.id)                               # eliminated last
  end

  it "keeps golden boot in goals order but still sinks eliminated to the bottom" do
    strong = create(:team)
    weak = create(:team)
    # Both must be round-of-16 teams to be golden-boot candidates.
    create(:match, stage: "r32", group_name: nil, kickoff_at: 5.days.from_now, home_team: strong, away_team: weak)
    7.times { create(:match, stage: "r32", group_name: nil, kickoff_at: 5.days.from_now) }
    [ [ strong, "Leader", 5 ], [ weak, "Trailer", 3 ] ].each do |team, player, goals|
      match = create(:match, home_team: team, away_team: create(:team))
      goals.times { create(:goal, match: match, team: team, player_name: player) }
    end
    create(:outright_ledger_entry, market: "golden_boot", subject_key: "scorer:#{strong.id}:Leader",
           subject_label: "Leader", team_id: strong.id, outcome: "lost", won: false, delta: -1.0)

    labels = OutrightBoard.new("golden_boot", nil).rows.map { |row| row.subject.subject_label }

    expect(labels.last).to eq("Leader") # eliminated sinks below the lower scorer
  end
end
