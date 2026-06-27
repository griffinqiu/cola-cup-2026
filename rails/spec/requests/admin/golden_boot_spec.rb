require "rails_helper"

RSpec.describe "Admin golden boot", type: :request do
  let(:settler) { create(:user) }

  around do |example|
    original = ENV["SETTLER_USERNAMES"]
    ENV["SETTLER_USERNAMES"] = "boss"
    example.run
    ENV["SETTLER_USERNAMES"] = original
  end

  before do
    create(:account, user: settler, username: "boss")
    sign_in settler
  end

  describe "POST /admin/golden_boot/open" do
    it "refuses before the final has a result" do
      post admin_golden_boot_open_path
      expect(response).to redirect_to(admin_settlements_path)
      follow_redirect!
      expect(response.body).to include("决赛尚未出结果")
    end

    it "reveals the top scorer and records the settler once the final is decided" do
      team = create(:team)
      goal_match = create(:match, home_team: team, away_team: create(:team))
      5.times { create(:goal, match: goal_match, team: team, player_name: "Top") }
      create(:outright_candidate, market: "golden_boot", subject_key: "scorer:#{team.id}:Top",
             subject_label: "Top", team_id: team.id, meta: { "team_id" => team.id, "goals_at_lock" => 5 })
      backer = create(:user)
      fader = create(:user)
      create(:outright_pick, user: backer, market: "golden_boot",
             subject_key: "scorer:#{team.id}:Top", subject_label: "Top", team_id: team.id, pick: "yes")
      create(:outright_pick, user: fader, market: "golden_boot",
             subject_key: "scorer:#{team.id}:Top", subject_label: "Top", team_id: team.id, pick: "no")
      create(:match, stage: "final", group_name: nil, home_team: team, away_team: create(:team),
             result: "home", result_at: Time.current)

      post admin_golden_boot_open_path

      expect(response).to redirect_to(admin_settlements_path)
      entry = OutrightLedgerEntry.find_by(user: backer)
      expect(entry.outcome).to eq("won_title")
      expect(entry.delta).to eq(1.0)
      expect(entry.settled_by_id).to eq(settler.id)
    end
  end

  describe "GET /admin/settlements?tab=records" do
    it "renders the outright settlement section" do
      get admin_settlements_path(tab: "records")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("竞猜结算")
    end
  end
end
