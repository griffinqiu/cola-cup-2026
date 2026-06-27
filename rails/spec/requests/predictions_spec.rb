require "rails_helper"

RSpec.describe "Predictions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }

  # 8 round-of-16 matches with teams and a future kickoff -> field set & window open.
  def open_r16_field!
    8.times { create(:match, stage: "r16", group_name: nil, kickoff_at: 5.days.from_now) }
  end

  describe "GET /predictions" do
    it "renders the not-open state before any round-of-16 team is known" do
      get predictions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("竞猜将在 16 强产生后开放")
    end

    it "renders champion candidate cards and the countdown once the field is set" do
      open_r16_field!
      team = Match.where(stage: "r16").first.home_team

      get predictions_path(tab: "champion")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("距封盘")
      expect(response.body).to include(team.display_name)
    end

    it "renders golden boot candidates (round-of-16 players with >= 3 goals)" do
      open_r16_field!
      team = Match.where(stage: "r16").first.home_team
      match = create(:match, home_team: team, away_team: create(:team))
      3.times { create(:goal, match: match, team: team, player_name: "Ronaldo") }

      get predictions_path(tab: "golden_boot")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ronaldo")
    end
  end

  describe "POST /outright_picks" do
    it "sends anonymous visitors to the identity prompt" do
      post outright_picks_path, params: { market: "champion", subject_key: "team:1", pick: "yes", stake: "1" }
      expect(response).to redirect_to(identity_path)
      expect(OutrightPick.count).to eq(0)
    end

    it "casts a champion pick with the chosen stake while the window is open" do
      sign_in user
      open_r16_field!
      team = Match.where(stage: "r16").first.home_team

      post outright_picks_path,
           params: { market: "champion", subject_key: "team:#{team.id}", pick: "yes", stake: "3" },
           as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(OutrightPick.sole).to have_attributes(
        user_id: user.id, market: "champion", subject_key: "team:#{team.id}", pick: "yes", stake: 3.0
      )
    end

    it "rejects an out-of-range stake (no pick written)" do
      sign_in user
      open_r16_field!
      team = Match.where(stage: "r16").first.home_team

      post outright_picks_path,
           params: { market: "champion", subject_key: "team:#{team.id}", pick: "yes", stake: "5" },
           as: :turbo_stream

      expect(OutrightPick.count).to eq(0)
    end

    it "rejects a pick when betting is not open" do
      sign_in user
      post outright_picks_path,
           params: { market: "champion", subject_key: "team:1", pick: "yes", stake: "1" }, as: :turbo_stream
      expect(OutrightPick.count).to eq(0)
    end

    it "opens a team as soon as it reaches the round of 16 (no full field needed)" do
      sign_in user
      match = create(:match, stage: "r16", group_name: nil, kickoff_at: 5.days.from_now)
      team = match.home_team

      post outright_picks_path,
           params: { market: "champion", subject_key: "team:#{team.id}", pick: "yes", stake: "1" }, as: :turbo_stream

      expect(OutrightPick.sole).to have_attributes(subject_key: "team:#{team.id}", pick: "yes")
    end

    it "upserts in place when the side or stake changes" do
      sign_in user
      open_r16_field!
      team = Match.where(stage: "r16").first.home_team
      subject = { market: "champion", subject_key: "team:#{team.id}" }

      post outright_picks_path, params: subject.merge(pick: "yes", stake: "1"), as: :turbo_stream
      expect { post outright_picks_path, params: subject.merge(pick: "no", stake: "2"), as: :turbo_stream }
        .not_to change(OutrightPick, :count)
      expect(user.outright_picks.sole).to have_attributes(pick: "no", stake: 2.0)
    end

    it "cancels a pick via DELETE" do
      sign_in user
      open_r16_field!
      team = Match.where(stage: "r16").first.home_team
      post outright_picks_path,
           params: { market: "champion", subject_key: "team:#{team.id}", pick: "yes", stake: "2" },
           as: :turbo_stream

      delete outright_picks_path,
             params: { market: "champion", subject_key: "team:#{team.id}" }, as: :turbo_stream

      expect(OutrightPick.count).to eq(0)
    end
  end
end
