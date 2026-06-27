require "rails_helper"

RSpec.describe "Locale selection" do
  include Devise::Test::IntegrationHelpers

  describe "resolution order" do
    it "honors an explicit ?locale= param above everything else" do
      get root_path(locale: "ja")
      expect(html_lang).to eq("ja")
    end

    it "falls back to the Accept-Language header for anonymous visitors" do
      get root_path, headers: { "Accept-Language" => "ja,en;q=0.5" }
      expect(html_lang).to eq("ja")
    end

    it "uses the signed-in user's saved locale over the browser header" do
      sign_in create(:user, locale: "en")
      get root_path, headers: { "Accept-Language" => "ja" }
      expect(html_lang).to eq("en")
    end

    it "defaults to zh-CN when nothing else applies" do
      get root_path, headers: { "Accept-Language" => "fr,de" }
      expect(html_lang).to eq("zh-CN")
    end
  end

  describe "PATCH /locale" do
    it "persists an anonymous visitor's choice in a cookie" do
      patch locale_path, params: { locale: "ja" }
      expect(response).to have_http_status(:see_other)

      get root_path
      expect(html_lang).to eq("ja")
    end

    it "saves a signed-in user's choice without bumping updated_at" do
      user = create(:user, locale: "zh-CN")
      sign_in user
      expect {
        patch locale_path, params: { locale: "en" }
      }.not_to change { user.reload.updated_at }
      expect(user.reload.locale).to eq("en")
    end

    it "ignores an unsupported locale" do
      patch locale_path, params: { locale: "fr" }
      get root_path
      expect(html_lang).to eq("zh-CN")
    end
  end

  def html_lang
    response.body[/<html[^>]*\blang="([^"]+)"/, 1]
  end
end
