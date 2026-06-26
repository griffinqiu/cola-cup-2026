require "rails_helper"

RSpec.describe "Votes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user) }

  describe "POST /matches/:id/vote" do
    it "sends anonymous visitors to the identity prompt" do
      match = create(:match)
      post match_vote_path(match), params: { pick: "home" }
      expect(response).to redirect_to(identity_path)
      expect(Vote.count).to eq(0)
    end

    it "records a vote with a stake the player chose from the stage's options" do
      sign_in user
      match = create(:match, :knockout) # r16 -> options [2, 3]
      post match_vote_path(match), params: { pick: "home", stake: "3" }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      vote = Vote.sole
      expect(vote).to have_attributes(user_id: user.id, match_id: match.id, pick: "home", stake: 3.0)
    end

    it "rejects a stake outside the stage's options (422, no vote written)" do
      sign_in user
      match = create(:match, :knockout) # r16 -> options [2, 3], so 5 is invalid
      post match_vote_path(match), params: { pick: "home", stake: "5" }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("该比赛不支持这个押注瓶数")
      expect(Vote.count).to eq(0)
    end

    it "upserts in place when only the stake changes" do
      sign_in user
      match = create(:match, :knockout)
      post match_vote_path(match), params: { pick: "home", stake: "2" }, as: :turbo_stream
      expect { post match_vote_path(match), params: { pick: "home", stake: "3" }, as: :turbo_stream }
        .not_to change(Vote, :count)
      expect(user.votes.find_by(match: match).stake).to eq(3.0)
    end

    it "upserts in place when the pick changes" do
      sign_in user
      match = create(:match) # group -> stake fixed at 1
      post match_vote_path(match), params: { pick: "home", stake: "1" }, as: :turbo_stream
      expect { post match_vote_path(match), params: { pick: "away", stake: "1" }, as: :turbo_stream }
        .not_to change(Vote, :count)
      expect(user.votes.find_by(match: match).pick).to eq("away")
    end

    it "rejects a pick the stage does not allow (409→422)" do
      sign_in user
      match = create(:match, :knockout) # no draw in knockout
      post match_vote_path(match), params: { pick: "draw" }, as: :turbo_stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("该比赛不支持这个投注选项")
      expect(Vote.count).to eq(0)
    end

    it "blocks voting once the window has closed (409, no vote written)" do
      sign_in user
      match = create(:match, :locked) # within 1h of kickoff -> :locked
      post match_vote_path(match), params: { pick: "home", stake: "1" }, as: :turbo_stream
      expect(response).to have_http_status(:conflict)
      expect(Vote.count).to eq(0)
    end
  end

  describe "the interactive panel on a votable match" do
    it "renders the picker form wired to the vote-panel + countdown controllers" do
      sign_in user
      match = create(:match)
      get match_path(match)
      expect(response.body).to include('data-controller="vote-panel countdown"')
      expect(response.body).to include("data-vote-panel-target=\"pick\"")
      expect(response.body).to include("你看好谁？")
      expect(response.body).to include(match.home_team.display_name)
    end

    it "renders the bottle-amount selector for a knockout match" do
      sign_in user
      match = create(:match, :knockout) # r16 -> options [2, 3], default 3
      get match_path(match)
      expect(response.body).to include('data-vote-panel-target="stake"')
      expect(response.body).to include('data-stake="2.0"')
      expect(response.body).to include('data-stake="3.0"')
      expect(response.body).to include('data-vote-panel-default-stake-value="3.0"')
      expect(response.body).not_to include("本场固定下注")
    end

    it "keeps the stake fixed (no selector) for a group match" do
      sign_in user
      match = create(:match) # group -> fixed 1 bottle
      get match_path(match)
      expect(response.body).not_to include('data-vote-panel-target="stake"')
      expect(response.body).to include("本场固定下注")
    end
  end

  describe "DELETE /matches/:id/vote" do
    it "removes the player's vote" do
      sign_in user
      match = create(:match)
      create(:vote, match: match, user: user, pick: "home", stake: match.stake)
      expect { delete match_vote_path(match), as: :turbo_stream }.to change(Vote, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end

    it "blocks cancellation once locked (409)" do
      sign_in user
      match = create(:match, :locked)
      create(:vote, match: match, user: user, pick: "home", stake: 1.0)
      delete match_vote_path(match), as: :turbo_stream
      expect(response).to have_http_status(:conflict)
      expect(Vote.count).to eq(1)
    end
  end
end
