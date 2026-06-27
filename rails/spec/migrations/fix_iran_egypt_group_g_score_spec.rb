require "rails_helper"
require Rails.root.join("db/migrate/20260627100000_fix_iran_egypt_group_g_score")

# Exercises the one-off data fix directly (not through the migrator), so the
# guard, the ledger re-settlement, and the standings knock-on are all covered.
RSpec.describe FixIranEgyptGroupGScore do
  EXTERNAL_KEY = "Matchday 16|2026-06-26|Egypt|Iran".freeze

  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  # The Group G fixture as the bad source left it: Egypt (home) 1 - 2 Iran (away),
  # settled as an away win, with the ledger paid out on that wrong result.
  def buggy_match
    egypt = create(:team, code: "EGY", name: "Egypt", name_zh: "埃及")
    iran = create(:team, code: "IRN", name: "Iran", name_zh: "伊朗")
    create(
      :match, :settled, external_key: EXTERNAL_KEY, stage: "group", group_name: "Group G",
      home_team: egypt, away_team: iran, home_score: 1, away_score: 2, result: "away"
    )
  end

  # Three 1-bottle voters: one on each outcome. Their ledger reflects the old
  # "away" settlement (away +2, home/draw each -1).
  def settle_three_voters(match)
    home = create(:user)
    draw = create(:user)
    away = create(:user)
    create(:vote, match: match, user: home, pick: "home", stake: 1.0)
    create(:vote, match: match, user: draw, pick: "draw", stake: 1.0)
    create(:vote, match: match, user: away, pick: "away", stake: 1.0)
    create(:ledger_entry, match: match, user: home, pick: "home", stake: 1.0, won: false, delta: -1.0, d_used: 3.0)
    create(:ledger_entry, match: match, user: draw, pick: "draw", stake: 1.0, won: false, delta: -1.0, d_used: 3.0)
    create(:ledger_entry, match: match, user: away, pick: "away", stake: 1.0, won: true,  delta: 2.0,  d_used: 3.0)
    { home: home, draw: draw, away: away }
  end

  def delta_for(match, user)
    LedgerEntry.find_by(match_id: match.id, user_id: user.id).delta
  end

  it "corrects the scoreline to a 1:1 draw, keeping it settled" do
    match = buggy_match

    run_migration

    match.reload
    expect(match.home_score).to eq(1)
    expect(match.away_score).to eq(1)
    expect(match.result).to eq("draw")
    expect(match.settled?).to be(true)
  end

  it "re-settles the cola: the draw backer now wins, the others forfeit their stake" do
    match = buggy_match
    voters = settle_three_voters(match)

    run_migration

    # Pool of 3 bottles, only the draw backer wins -> takes the other two stakes.
    expect(delta_for(match, voters[:draw])).to be_within(1e-9).of(2.0)
    expect(LedgerEntry.find_by(match_id: match.id, user_id: voters[:draw].id).won).to be(true)
    expect(delta_for(match, voters[:home])).to be_within(1e-9).of(-1.0)
    expect(delta_for(match, voters[:away])).to be_within(1e-9).of(-1.0)
    expect(match.ledger_entries.count).to eq(3)
  end

  it "feeds the corrected draw into the Group G standings" do
    match = buggy_match

    run_migration

    table = Standings::Group.find("G").rows.index_by(&:name)
    expect(table["Egypt"].drawn).to eq(1)
    expect(table["Iran"].drawn).to eq(1)
    expect(table["Egypt"].won).to eq(0)
    expect(table["Egypt"].points).to eq(1)
    expect(table["Iran"].points).to eq(1)
    expect(table["Egypt"].goal_diff).to eq(0)
  end

  it "is idempotent: a second run is a no-op" do
    match = buggy_match
    voters = settle_three_voters(match)

    run_migration
    deltas_after_first = match.ledger_entries.order(:user_id).pluck(:user_id, :delta)

    run_migration

    expect(match.reload.result).to eq("draw")
    expect(match.ledger_entries.order(:user_id).pluck(:user_id, :delta)).to eq(deltas_after_first)
  end

  it "leaves an unrelated / already-corrected match untouched" do
    egypt = create(:team, code: "EGY", name: "Egypt", name_zh: "埃及")
    iran = create(:team, code: "IRN", name: "Iran", name_zh: "伊朗")
    # Same fixture, but already a 1:1 draw (e.g. hand-fixed beforehand).
    create(
      :match, :settled, external_key: EXTERNAL_KEY, stage: "group", group_name: "Group G",
      home_team: egypt, away_team: iran, home_score: 1, away_score: 1, result: "draw"
    )

    expect { run_migration }.not_to(change { Match.find_by(external_key: EXTERNAL_KEY).attributes })
  end
end
