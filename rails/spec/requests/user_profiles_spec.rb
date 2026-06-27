require "rails_helper"

# Public per-user detail reached from the leaderboard: a read-only view of
# someone's settlement records (结算记录) plus their redemption records (兑换记录).
RSpec.describe "GET /users/:id", type: :request do
  include Devise::Test::IntegrationHelpers

  it "redirects anonymous visitors to the identity prompt" do
    user = create(:user)
    get user_path(user)
    expect(response).to redirect_to(identity_path)
  end

  it "shows the user's settlement records and redemption records" do
    viewer = create(:user)
    target = create(:user, nickname: "阿强", emoji: "🦊")
    won_match = create(:match, :settled)
    lost_match = create(:match, :settled)
    create(:ledger_entry, user: target, match: won_match, won: true, stake: 1.0, d_used: 7.0, delta: 6.0)
    create(:ledger_entry, user: target, match: lost_match, won: false, stake: 1.0, d_used: 2.0, delta: -1.0)
    create(:redemption, user: target, drink: "cola", qty: 2, cost: 2.0)
    sign_in viewer

    get user_path(target)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("阿强", "结算记录", "兑换记录")
    expect(response.body).to include(won_match.home_team.display_name)
    expect(response.body).to include("押 1 瓶")
    expect(response.body).not_to include("赔")
    expect(response.body).not_to include("未中")
    expect(response.body).to include(%(href="#{match_path(won_match)}"))
    expect(response.body).not_to include("结算明细")
  end

  it "shows the user's outright (champion/golden boot) settlement records" do
    viewer = create(:user)
    target = create(:user, nickname: "阿强")
    team = create(:team, name: "Argentina", name_zh: "阿根廷")
    create(:outright_ledger_entry, user: target, market: "champion",
           subject_key: "team:#{team.id}", subject_label: "阿根廷", team: team,
           pick: "yes", stake: 2.0, d_used: 2.0, won: false, delta: -2.0, outcome: "lost")
    sign_in viewer

    get user_path(target)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("竞猜结算", "阿根廷")
    expect(response.body).to include("2.00")
    expect(response.body).to include(%(href="#{predictions_path(tab: "champion")}"))
  end

  it "404s for a soft-deleted user" do
    viewer = create(:user)
    target = create(:user)
    target.soft_delete!
    sign_in viewer

    get user_path(target)
    expect(response).to have_http_status(:not_found)
  end
end
