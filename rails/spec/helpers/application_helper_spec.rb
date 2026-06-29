require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#nav_tab_active?" do
    def on(path)
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: path))
    end

    it "lights up the schedule tab across the whole match-browsing flow" do
      [ "/", "/matches/42", "/groups", "/groups/A", "/scorers", "/third-place", "/teams/7" ].each do |path|
        on(path)
        expect(helper.nav_tab_active?("/")).to be(true), "expected schedule tab active on #{path}"
      end
    end

    it "leaves the schedule tab inactive on unrelated sections" do
      [ "/me", "/me/settings", "/predictions", "/leaderboard" ].each do |path|
        on(path)
        expect(helper.nav_tab_active?("/")).to be(false), "expected schedule tab inactive on #{path}"
      end
    end

    it "keeps /me exact so the settings page does not also light up redeem" do
      on("/me")
      expect(helper.nav_tab_active?("/me")).to be(true)
      expect(helper.nav_tab_active?("/me/settings")).to be(false)

      on("/me/settings")
      expect(helper.nav_tab_active?("/me")).to be(false)
      expect(helper.nav_tab_active?("/me/settings")).to be(true)
    end

    it "matches the remaining tabs by path prefix" do
      on("/predictions")
      expect(helper.nav_tab_active?("/predictions")).to be(true)

      on("/leaderboard")
      expect(helper.nav_tab_active?("/leaderboard")).to be(true)
    end
  end
end
