require "rails_helper"

RSpec.describe User do
  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:nickname) }
    it { is_expected.to validate_length_of(:nickname).is_at_most(16) }
    it { is_expected.to validate_inclusion_of(:locale).in_array(User::LOCALES) }
  end

  describe "#net_balance" do
    it "is settled net (Σ delta) minus credits spent on drinks" do
      user = create(:user)
      create(:ledger_entry, user: user, delta: 3.0)
      create(:ledger_entry, user: user, delta: -1.0)
      create(:redemption, user: user, cost: 1.5)

      expect(user.net_balance).to be_within(1e-9).of(0.5)
    end
  end

  describe "soft delete" do
    it "marks and restores deleted_at and excludes from .active" do
      user = create(:user)
      user.soft_delete!
      expect(user.deleted?).to be(true)
      expect(User.active).not_to include(user)

      user.restore!
      expect(user.reload.deleted_at).to be_nil
      expect(User.active).to include(user)
    end
  end

  describe ".leaderboard" do
    it "ranks by total desc, then bets desc, then created_at; excludes soft-deleted" do
      leader = create(:user, created_at: 3.days.ago)
      runner_up = create(:user, created_at: 2.days.ago)
      hidden = create(:user, :deleted)

      create(:ledger_entry, user: leader, delta: 5.0, won: true)
      create(:ledger_entry, user: runner_up, delta: 2.0, won: true)
      create(:ledger_entry, user: runner_up, delta: 0.0, won: false)
      create(:ledger_entry, user: hidden, delta: 99.0, won: true)
      # Redemptions never lower the rank.
      create(:redemption, user: leader, cost: 4.0)

      board = User.leaderboard.to_a
      expect(board.map(&:id)).to eq([ leader.id, runner_up.id ])
      expect(board.first.total).to be_within(1e-9).of(5.0)
      expect(board.first.redeemed).to be_within(1e-9).of(4.0)
      expect(board.last.bets).to eq(2)
      expect(board.map(&:id)).not_to include(hidden.id)
    end
  end

  describe ".board_for" do
    it "resolves a known key and falls back to the default (镰刀榜) otherwise" do
      expect(User.board_for("oracle").key).to eq("oracle")
      expect(User.board_for("nope")).to eq(User::DEFAULT_BOARD)
      expect(User.board_for(nil)).to eq(User::DEFAULT_BOARD)
      expect(User::DEFAULT_BOARD.key).to eq("reaper")
    end
  end

  describe ".bayesian_hit_score" do
    it "lets a high-volume record beat a lucky small sample at a modest mean" do
      mean = 1.0 / 3 # ≈ random three-way guessing
      proven = User.bayesian_hit_score(17, 20, mean)
      lucky = User.bayesian_hit_score(3, 3, mean)
      expect(proven).to be > lucky
    end
  end

  describe ".wilson_lower_bound" do
    it "ranks a proven positive rate above a tiny perfect sample" do
      expect(User.wilson_lower_bound(17, 20)).to be > User.wilson_lower_bound(3, 3)
    end

    it "is zero with no observations" do
      expect(User.wilson_lower_bound(0, 0)).to eq(0.0)
    end
  end

  describe ".leaderboard_for" do
    it "韭菜榜: net score ascending, dropping users who never bet" do
      big_loser = create(:user)
      small_loser = create(:user)
      spectator = create(:user)
      create(:ledger_entry, user: big_loser, delta: -5.0, won: false)
      create(:ledger_entry, user: small_loser, delta: -1.0, won: false)

      ids = User.leaderboard_for(User.board_for("leek")).map(&:id)
      expect(ids).to eq([ big_loser.id, small_loser.id ])
      expect(ids).not_to include(spectator.id)
    end

    it "肥宅榜: redeemed credits descending, dropping users with no redemptions" do
      glutton = create(:user)
      nibbler = create(:user)
      abstainer = create(:user)
      [ glutton, nibbler, abstainer ].each { |u| create(:ledger_entry, user: u, delta: 10.0, won: true) }
      create(:redemption, user: glutton, cost: 6.0)
      create(:redemption, user: nibbler, cost: 2.0)

      ids = User.leaderboard_for(User.board_for("otaku")).map(&:id)
      expect(ids).to eq([ glutton.id, nibbler.id ])
      expect(ids).not_to include(abstainer.id)
    end

    it "神预榜: a high-volume record outranks a lucky small sample (mean pulled down by cold users)" do
      proven = create(:user)
      lucky = create(:user)
      cold_a = create(:user)
      cold_b = create(:user)
      4.times { create(:ledger_entry, user: proven, won: true) }
      create(:ledger_entry, user: proven, won: false)
      2.times { create(:ledger_entry, user: lucky, won: true) }
      5.times { create(:ledger_entry, user: cold_a, won: false) }
      5.times { create(:ledger_entry, user: cold_b, won: false) }

      ids = User.leaderboard_for(User.board_for("oracle")).map(&:id)
      expect(ids.first(2)).to eq([ proven.id, lucky.id ])
    end

    it "毒奶榜: the most reliably wrong rank first; sharp pickers sink; non-bettors excluded" do
      reliable_jinx = create(:user) # 1/10
      small_jinx = create(:user)    # 0/2
      sharp = create(:user)         # 9/10
      spectator = create(:user)
      create(:ledger_entry, user: reliable_jinx, won: true)
      9.times { create(:ledger_entry, user: reliable_jinx, won: false) }
      2.times { create(:ledger_entry, user: small_jinx, won: false) }
      9.times { create(:ledger_entry, user: sharp, won: true) }
      create(:ledger_entry, user: sharp, won: false)

      ids = User.leaderboard_for(User.board_for("jinx")).map(&:id)
      expect(ids).to eq([ reliable_jinx.id, small_jinx.id, sharp.id ])
      expect(ids).not_to include(spectator.id)
    end
  end

  # The test env cache is :null_store (never caches), so swap in a real store to
  # exercise the signature-keyed caching and its self-invalidation.
  describe ".leaderboard caching" do
    let(:store) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(store) }

    it "returns Entry value objects whose to_param routes to the user" do
      user = create(:user)
      create(:ledger_entry, user: user, delta: 4.0, won: true)

      entry = User.leaderboard.first
      expect(entry).to be_a(User::Entry)
      expect(entry.to_param).to eq(user.id.to_s)
      expect(entry.total).to be_within(1e-9).of(4.0)
    end

    it "self-invalidates when a settlement inserts ledger rows via insert_all" do
      user = create(:user)
      create(:ledger_entry, user: user, delta: 2.0, won: true)
      expect(User.leaderboard.first.total).to be_within(1e-9).of(2.0)

      # Mirrors Settlement#write_ledger, which bypasses model callbacks.
      match = create(:match)
      LedgerEntry.insert_all([ {
        match_id: match.id, user_id: user.id, pick: "home", stake: 1.0,
        d_used: 2.0, won: true, delta: 3.0,
        created_at: Time.current, updated_at: Time.current
      } ])

      expect(User.leaderboard.first.total).to be_within(1e-9).of(5.0)
    end

    it "self-invalidates on a redemption and on a nickname edit" do
      user = create(:user, nickname: "旧名")
      create(:ledger_entry, user: user, delta: 1.0)
      expect(User.leaderboard.first.redeemed).to eq(0.0)

      create(:redemption, user: user, cost: 2.5)
      expect(User.leaderboard.first.redeemed).to be_within(1e-9).of(2.5)

      user.update!(nickname: "新名")
      expect(User.leaderboard.first.nickname).to eq("新名")
    end
  end

  describe "#settler?" do
    around do |example|
      original = ENV["SETTLER_USERNAMES"]
      example.run
      ENV["SETTLER_USERNAMES"] = original
    end

    it "is true when a linked account handle matches SETTLER_USERNAMES (@/case-insensitive)" do
      ENV["SETTLER_USERNAMES"] = "@Messi, other"
      user = create(:user)
      create(:account, user: user, username: "messi")

      expect(user.settler?).to be(true)
    end

    it "matches on the provider account id too" do
      ENV["SETTLER_USERNAMES"] = "12345"
      user = create(:user)
      create(:account, user: user, username: "nomatch", provider_account_id: "12345")

      expect(user.settler?).to be(true)
    end

    it "is false with no configured settlers" do
      ENV["SETTLER_USERNAMES"] = ""
      user = create(:user)
      create(:account, user: user, username: "messi")

      expect(user.settler?).to be(false)
    end
  end
end
