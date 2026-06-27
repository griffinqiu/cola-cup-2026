require "rails_helper"

# Covers the broadcast wiring two ways: (1) the after_commit triggers enqueue the
# right job, and (2) each job renders its fragments without error and broadcasts
# (the fragments must never reference current_user — they render session-less).
RSpec.describe "Broadcasts", type: :job do
  # A match with a voter and a market line, so every fragment has data to render.
  def rich_match(**attrs)
    match = create(:match, **attrs)
    create(:vote, match: match, user: create(:user), pick: "home", stake: 1.0)
    create(:odds_snapshot, match: match, source: "polymarket", locked: false,
      p_home: 0.6, p_away: 0.4, d_home: 1.67, d_away: 2.5, taken_at: Time.current)
    match
  end

  describe "after_commit triggers" do
    it "enqueues MatchOddsJob with include_votes on a vote change" do
      match = create(:match)
      expect { create(:vote, match: match, user: create(:user)) }
        .to have_enqueued_job(Broadcasts::MatchOddsJob).with(match.id, true)
    end

    it "enqueues MatchOddsJob without votes on a new odds snapshot" do
      match = create(:match)
      expect { create(:odds_snapshot, match: match) }
        .to have_enqueued_job(Broadcasts::MatchOddsJob).with(match.id, false)
    end

    it "enqueues MatchResultJob when a result is recorded" do
      match = create(:match, stage: "group")
      expect { match.record_result!(home_score: 2, away_score: 1) }
        .to have_enqueued_job(Broadcasts::MatchResultJob).with(match.id)
    end

    it "enqueues SettlementJob on commit" do
      match = create(:match, :with_result)
      create(:vote, match: match, user: create(:user), pick: "home", stake: 1.0)
      expect { Settlement.commit!([ match.id ], settler: create(:user)) }
        .to have_enqueued_job(Broadcasts::SettlementJob)
    end

    it "enqueues LeaderboardJob on a redemption" do
      user = create(:user)
      create(:ledger_entry, user: user, delta: 5.0)
      expect { Redemption.redeem!(user: user, drink_key: "cola", qty: 1) }
        .to have_enqueued_job(Broadcasts::LeaderboardJob)
    end

    it "distinguishes a profile edit from a visibility change" do
      user = create(:user)
      expect { user.update!(nickname: "新名") }.to have_enqueued_job(Broadcasts::ProfileJob).with(user.id)
      expect { user.soft_delete! }.to have_enqueued_job(Broadcasts::UserVisibilityJob).with(user.id)
    end
  end

  describe "fragment rendering (session-less)" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_call_original
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_to).and_call_original
    end

    it "MatchOddsJob renders odds bars, voter list and the schedule card" do
      match = rich_match
      expect { Broadcasts::MatchOddsJob.perform_now(match.id, true) }.not_to raise_error
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
    end

    it "MatchResultJob renders card fragments and refreshes the admin per locale" do
      match = rich_match(stage: "group")
      match.update_columns(result: "home", home_score: 2, away_score: 1)
      expect { Broadcasts::MatchResultJob.perform_now(match.id) }.not_to raise_error
      User::LOCALES.each do |locale|
        expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to).with("admin", locale)
      end
    end

    it "SettlementJob renders cards, leaderboard and ledgers" do
      match = create(:match, :with_result)
      create(:vote, match: match, user: create(:user), pick: "home", stake: 1.0)
      create(:vote, match: match, user: create(:user), pick: "away", stake: 1.0)
      result = Settlement.commit!([ match.id ], settler: create(:user))

      expect { Broadcasts::SettlementJob.perform_now(result.settlement.id) }.not_to raise_error
      User::LOCALES.each do |locale|
        expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_to).with("admin", locale)
      end
    end

    it "ProfileJob and UserVisibilityJob render the voter's matches" do
      match = rich_match
      voter = match.votes.first.user
      expect { Broadcasts::ProfileJob.perform_now(voter.id) }.not_to raise_error
      expect { Broadcasts::UserVisibilityJob.perform_now(voter.id) }.not_to raise_error
    end

    it "LeaderboardJob renders the board" do
      create(:ledger_entry, user: create(:user), delta: 3.0)
      expect { Broadcasts::LeaderboardJob.perform_now }.not_to raise_error
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
    end

    it "renders fragments without a signed-in user (no current_user leak)" do
      match = rich_match
      # No Devise session in a job context; rendering must not call current_user.
      expect { Broadcasts::MatchOddsJob.perform_now(match.id, true) }.not_to raise_error
    end
  end

  # The fragments must reach a per-locale stream, each rendered in that language,
  # so a viewer browsing in en/ja never gets a zh-CN live update.
  describe "per-locale streams" do
    it "broadcasts the leaderboard to one stream per supported locale" do
      create(:ledger_entry, user: create(:user), delta: 3.0)
      streams = []
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*streamables, **_opts|
        streams << streamables # e.g. ["leaderboard", :en]
      end

      Broadcasts::LeaderboardJob.perform_now

      expect(streams.map(&:first).uniq).to eq([ "leaderboard" ])
      expect(streams.map(&:last).map(&:to_s)).to match_array(User::LOCALES)
    end

    it "renders the voter-list fragment in each viewer's language" do
      match = rich_match # one voter, so the localized header always renders
      html = {}
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) do |*streamables, **opts|
        next unless opts[:target] == "votes_list_#{match.id}"

        html[streamables.last.to_s] = ApplicationController.render(
          partial: opts[:partial], locals: opts[:locals]
        )
      end

      Broadcasts::MatchOddsJob.perform_now(match.id, true)

      expect(html["zh-CN"]).to include("同事预测")
      expect(html["en"]).to include("Coworker predictions")
      expect(html["en"]).not_to include("同事预测")
      expect(html["ja"]).to include("同僚の予想")
    end
  end
end
