require "rails_helper"

RSpec.describe Match do
  describe "state machine #status" do
    let(:match) { create(:match) } # kickoff 3.days out, both teams set, unsettled

    it "is :settled whenever the match is settled, regardless of time" do
      settled = create(:match, :settled)
      expect(settled.status(now: settled.kickoff_at - 10.days)).to eq(:settled)
      expect(settled.status(now: settled.kickoff_at + 10.days)).to eq(:settled)
    end

    it "locks exactly at vote_closes_at (1h before kickoff), to ±1s" do
      close = match.vote_closes_at
      expect(match.status(now: close - 1.second)).not_to eq(:locked)
      expect(match.status(now: close)).to eq(:locked)
      expect(match.status(now: close + 1.second)).to eq(:locked)
    end

    it "is :scheduled until vote_opens_at, to ±1s" do
      open = match.vote_opens_at
      expect(match.status(now: open - 1.second)).to eq(:scheduled)
      expect(match.status(now: open)).not_to eq(:scheduled)
      expect(match.status(now: open)).to eq(:open)
    end

    it "opens voting at Beijing midnight 6 days before the kickoff date" do
      # Kickoff Monday 2026-06-22 20:00 Beijing (12:00 UTC) -> opens the
      # previous Tuesday 2026-06-16 00:00 Beijing (06-15 16:00 UTC).
      monday_match = create(:match, kickoff_at: Time.utc(2026, 6, 22, 12, 0))
      expect(monday_match.vote_opens_at).to eq(Time.utc(2026, 6, 15, 16, 0))

      # A 00:30 Beijing kickoff still counts by its calendar day.
      early_match = create(:match, kickoff_at: Time.utc(2026, 6, 21, 16, 30))
      expect(early_match.vote_opens_at).to eq(Time.utc(2026, 6, 15, 16, 0))
    end

    it "is :open inside the window when both teams are set" do
      expect(match.status(now: match.vote_closes_at - 1.second)).to eq(:open)
      expect(match.votable?(now: match.vote_closes_at - 1.second)).to be(true)
    end

    it "is :upcoming inside the window when a team is undetermined" do
      tbd = create(:match, :no_teams)
      expect(tbd.bettable?).to be(false)
      expect(tbd.status).to eq(:upcoming)
      expect(tbd.votable?).to be(false)
    end

    it "is not votable once locked" do
      expect(match.votable?(now: match.vote_closes_at)).to be(false)
    end

    it "is :live from kickoff until a result is recorded" do
      live = create(:match, kickoff_at: 1.hour.ago)
      expect(live.status).to eq(:live)
      expect(live.votable?).to be(false)

      live.record_result!(home_score: 1, away_score: 0)
      expect(live.status).to eq(:locked)
    end

    it "falls back from :live to :locked after LIVE_WINDOW without a result" do
      stale = create(:match, kickoff_at: (Match::LIVE_WINDOW + 1.minute).ago)
      expect(stale.status).to eq(:locked)
    end
  end

  describe "#record_live_score!" do
    let(:live_match) { create(:match, kickoff_at: 30.minutes.ago) }

    it "updates the score without touching the result (so nothing can settle early)" do
      expect(live_match.record_live_score!(home_score: 1, away_score: 0)).to be(true)

      live_match.reload
      expect(live_match.home_score).to eq(1)
      expect(live_match.away_score).to eq(0)
      expect(live_match.result).to be_nil
      expect(live_match.settled).to be(false)
      expect(live_match.status).to eq(:live)
    end

    it "does not enqueue an auto-settlement" do
      expect { live_match.record_live_score!(home_score: 1, away_score: 0) }
        .not_to have_enqueued_job(AutoSettleJob)
    end

    it "refuses once a result is recorded or the match is settled" do
      finished = create(:match, :with_result, kickoff_at: 2.hours.ago)
      expect(finished.record_live_score!(home_score: 9, away_score: 9)).to be(false)
      expect(finished.reload.home_score).to eq(2)

      settled = create(:match, :settled)
      expect(settled.record_live_score!(home_score: 9, away_score: 9)).to be(false)
    end

    it "no-ops on an unchanged score" do
      live_match.record_live_score!(home_score: 1, away_score: 0)
      expect(live_match.record_live_score!(home_score: 1, away_score: 0)).to be(false)
    end
  end

  describe "stage rules" do
    it "exposes the per-stage stake options with a middle default" do
      group = build(:match, stage: "group")
      expect(group.stake_options).to eq([ 1.0 ])
      expect(group.default_stake).to eq(1.0)
      expect(group.stake).to eq(1.0)

      r16 = build(:match, stage: "r16")
      expect(r16.stake_options).to eq([ 2.0, 3.0 ])
      expect(r16.default_stake).to eq(3.0)

      final = build(:match, stage: "final")
      expect(final.stake_options).to eq([ 3.0, 5.0 ])
      expect(final.default_stake).to eq(5.0)
    end

    it "accepts only stakes within the stage's options" do
      r16 = build(:match, stage: "r16")
      expect(r16.valid_stake?(2.0)).to be(true)
      expect(r16.valid_stake?(3)).to be(true)
      expect(r16.valid_stake?(4.0)).to be(false)
      expect(r16.valid_stake?(999)).to be(false)

      expect(build(:match, stage: "sf").valid_stake?(5.0)).to be(true)
      expect(build(:match, stage: "third").valid_stake?(5.0)).to be(true)
      expect(build(:match, stage: "sf").valid_stake?(9.0)).to be(false)
      expect(build(:match, stage: "group").valid_stake?(1.0)).to be(true)
      expect(build(:match, stage: "group").valid_stake?(2.0)).to be(false)
    end

    it "allows a draw only outside the knockout rounds" do
      expect(build(:match, stage: "group").allows_draw?).to be(true)
      expect(build(:match, stage: "group").valid_picks).to eq(%w[home draw away])

      expect(build(:match, stage: "r16").knockout?).to be(true)
      expect(build(:match, stage: "r16").allows_draw?).to be(false)
      expect(build(:match, stage: "r16").valid_picks).to eq(%w[home away])
    end
  end

  describe "#derive_result_from_score" do
    it "derives home/away from the scoreline" do
      match = build(:match, stage: "group")
      expect(match.derive_result_from_score(2, 1)).to eq("home")
      expect(match.derive_result_from_score(0, 3)).to eq("away")
    end

    it "derives a draw for level group games but nil for level knockouts" do
      expect(build(:match, stage: "group").derive_result_from_score(1, 1)).to eq("draw")
      expect(build(:match, stage: "r16").derive_result_from_score(1, 1)).to be_nil
    end

    it "is nil without a complete score" do
      expect(build(:match).derive_result_from_score(nil, 1)).to be_nil
      expect(build(:match).derive_result_from_score(1, nil)).to be_nil
    end
  end

  describe "#record_result!" do
    it "records a derived result on an unsettled match" do
      match = create(:match, stage: "group")
      match.record_result!(home_score: 2, away_score: 1)
      expect(match.reload.result).to eq("home")
      expect(match.home_score).to eq(2)
      expect(match.result_at).to be_present
      expect(match.settled?).to be(false)
    end

    it "requires an explicit advancer for a level knockout (Chinese message)" do
      match = create(:match, :knockout)
      expect { match.record_result!(home_score: 1, away_score: 1) }
        .to raise_error(Match::DomainError, "淘汰赛比分相同，请选择晋级方")

      match.record_result!(home_score: 1, away_score: 1, result: "home")
      expect(match.reload.result).to eq("home")
    end

    it "rejects an explicit draw for a knockout (a live-sync DRAW before the shootout winner posts)" do
      match = create(:match, :knockout)
      expect { match.record_result!(home_score: 1, away_score: 1, result: "draw") }
        .to raise_error(Match::DomainError, "淘汰赛比分相同，请选择晋级方")
      expect(match.reload.result).to be_nil
    end

    it "refuses to re-record a settled match (use display-score edit instead)" do
      match = create(:match, :settled)
      expect { match.record_result!(home_score: 3, away_score: 0) }
        .to raise_error(Match::DomainError, "该比赛已结算，请用修改比分")
    end
  end

  describe "#update_display_score!" do
    it "edits a settled match's score without touching the result or settled flag" do
      match = create(:match, :settled) # result "home", 2-1
      match.update_display_score!(home_score: 4, away_score: 0)

      match.reload
      expect(match.home_score).to eq(4)
      expect(match.away_score).to eq(0)
      expect(match.result).to eq("home")
      expect(match.settled?).to be(true)
    end
  end

  describe "scopes" do
    it ".settle_todo lists kicked-off, unsettled matches chronologically" do
      now = Time.current
      past_unsettled = create(:match, kickoff_at: now - 2.hours)
      older_unsettled = create(:match, kickoff_at: now - 5.hours)
      create(:match, :settled, kickoff_at: now - 3.hours)
      create(:match, kickoff_at: now + 5.hours) # not kicked off

      expect(Match.settle_todo(now)).to eq([ older_unsettled, past_unsettled ])
    end

    it ".due_for_lock includes matches whose voting window has closed" do
      now = Time.current
      due = create(:match, kickoff_at: now + 30.minutes) # closes 1h before -> already closed
      create(:match, kickoff_at: now + 5.hours)          # still open
      create(:match, :settled, kickoff_at: now + 10.minutes)

      expect(Match.due_for_lock(now)).to contain_exactly(due)
    end
  end
end
