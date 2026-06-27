require "rails_helper"

# Integration coverage for the Twitter callback. The devise_for block in
# routes.rb is enabled by team-lead at the end of 阶段4; until then the named
# route is absent and these examples are pending (they activate automatically
# once the routes land).
RSpec.describe "Users::OmniauthCallbacks", type: :request do
  before do
    unless Rails.application.routes.url_helpers.respond_to?(:user_twitter2_omniauth_callback_path)
      skip "devise_for routes not enabled yet (team-lead to uncomment in routes.rb)"
    end

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:twitter2] = OmniAuth::AuthHash.new(
      provider: "twitter2", uid: "4242",
      info: { name: "Test Fan", nickname: "testfan", image: "https://x/a_normal.jpg" }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:twitter2]
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:twitter2] = nil
    Rails.application.env_config.delete("omniauth.auth")
  end

  it "creates the user on first login and redirects to profile setup (no emoji yet)" do
    expect { post user_twitter2_omniauth_callback_path }.to change(User, :count).by(1)
    expect(response).to redirect_to(me_settings_path)
  end

  it "generates the first-time fallback nickname in the visitor's locale" do
    # Blank provider name → User.nickname_from falls back to the localized
    # default. The Devise controller must run under the app's switch_locale
    # (config.parent_controller = ApplicationController) for this to honor the
    # visitor's language rather than always the zh-CN default.
    OmniAuth.config.mock_auth[:twitter2] = OmniAuth::AuthHash.new(
      provider: "twitter2", uid: "9001", info: { name: "", nickname: "x", image: "" }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:twitter2]

    post user_twitter2_omniauth_callback_path, headers: { "Accept-Language" => "ja" }
    expect(User.last.nickname).to eq(I18n.t("users.fallback_nickname", locale: :ja))
  end

  it "sends a returning user (emoji set) to their dashboard" do
    User.from_omniauth(OmniAuth.config.mock_auth[:twitter2]).update!(emoji: "🐉")

    post user_twitter2_omniauth_callback_path
    expect(response).to redirect_to(me_path)
  end

  context "OIDC callback" do
    before do
      unless Rails.application.routes.url_helpers.respond_to?(:user_openid_connect_omniauth_callback_path)
        skip "openid_connect not in omniauth_providers yet"
      end

      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(
        provider: "openid_connect", uid: "sub-9",
        info: { name: "Test OIDC", nickname: "oidcfan", image: "https://idp/p.png" }
      )
      Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:openid_connect]
    end

    after do
      OmniAuth.config.test_mode = false
      OmniAuth.config.mock_auth[:openid_connect] = nil
      Rails.application.env_config.delete("omniauth.auth")
    end

    it "creates the user on first OIDC login and redirects to profile setup" do
      expect { post user_openid_connect_omniauth_callback_path }.to change(User, :count).by(1)
      expect(response).to redirect_to(me_settings_path)
      expect(User.last.accounts.first.provider).to eq("oidc")
    end

    it "sends a returning OIDC user (emoji set) to their dashboard" do
      User.from_omniauth(OmniAuth.config.mock_auth[:openid_connect]).update!(emoji: "🐉")
      post user_openid_connect_omniauth_callback_path
      expect(response).to redirect_to(me_path)
    end
  end
end
