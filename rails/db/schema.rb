# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_27_100012) do
  create_table "accounts", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "provider_account_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "username"
    t.index ["provider", "provider_account_id"], name: "index_accounts_on_provider_and_provider_account_id", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "goals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "match_id", null: false
    t.integer "minute"
    t.boolean "own_goal", default: false, null: false
    t.boolean "penalty", default: false, null: false
    t.string "player_name", null: false
    t.integer "team_id"
    t.datetime "updated_at", null: false
    t.index ["match_id"], name: "index_goals_on_match_id"
    t.index ["player_name", "team_id"], name: "index_goals_on_player_name_and_team_id"
    t.index ["team_id"], name: "index_goals_on_team_id"
  end

  create_table "ledger_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "d_used", null: false
    t.float "delta", null: false
    t.integer "match_id", null: false
    t.string "pick", null: false
    t.float "stake", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "won", null: false
    t.index ["match_id", "user_id"], name: "index_ledger_entries_on_match_id_and_user_id", unique: true
    t.index ["match_id"], name: "index_ledger_entries_on_match_id"
    t.index ["user_id"], name: "index_ledger_entries_on_user_id"
  end

  create_table "matches", force: :cascade do |t|
    t.string "away_label"
    t.integer "away_score"
    t.integer "away_team_id"
    t.datetime "created_at", null: false
    t.string "external_key", null: false
    t.string "group_name"
    t.string "home_label"
    t.integer "home_score"
    t.integer "home_team_id"
    t.datetime "kickoff_at", null: false
    t.string "result"
    t.datetime "result_at"
    t.boolean "settled", default: false, null: false
    t.integer "settlement_id"
    t.string "stage", null: false
    t.datetime "updated_at", null: false
    t.string "venue"
    t.index ["away_team_id"], name: "index_matches_on_away_team_id"
    t.index ["external_key"], name: "index_matches_on_external_key", unique: true
    t.index ["home_team_id"], name: "index_matches_on_home_team_id"
    t.index ["kickoff_at"], name: "index_matches_on_kickoff_at"
    t.index ["settlement_id"], name: "index_matches_on_settlement_id"
    t.index ["stage"], name: "index_matches_on_stage"
  end

  create_table "odds_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "d_away"
    t.float "d_draw"
    t.float "d_home"
    t.boolean "locked", default: false, null: false
    t.integer "match_id", null: false
    t.float "p_away"
    t.float "p_draw"
    t.float "p_home"
    t.string "source", null: false
    t.datetime "taken_at", null: false
    t.datetime "updated_at", null: false
    t.index ["match_id", "source", "locked"], name: "index_odds_snapshots_on_match_id_and_source_and_locked"
    t.index ["match_id"], name: "index_odds_snapshots_on_match_id"
  end

  create_table "outright_candidates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "frozen_at", null: false
    t.string "market", null: false
    t.json "meta"
    t.string "subject_key", null: false
    t.string "subject_label", null: false
    t.integer "team_id"
    t.datetime "updated_at", null: false
    t.index ["market", "subject_key"], name: "index_outright_candidates_on_market_and_subject_key", unique: true
    t.index ["team_id"], name: "index_outright_candidates_on_team_id"
  end

  create_table "outright_ledger_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "d_used", null: false
    t.float "delta", null: false
    t.string "market", null: false
    t.string "outcome", null: false
    t.string "pick", null: false
    t.datetime "settled_at", null: false
    t.integer "settled_by_id"
    t.integer "source_match_id"
    t.float "stake", null: false
    t.string "subject_key", null: false
    t.string "subject_label", null: false
    t.integer "team_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "won", null: false
    t.index ["market", "subject_key"], name: "index_outright_ledger_entries_on_market_and_subject_key"
    t.index ["settled_by_id"], name: "index_outright_ledger_entries_on_settled_by_id"
    t.index ["source_match_id"], name: "index_outright_ledger_entries_on_source_match_id"
    t.index ["team_id"], name: "index_outright_ledger_entries_on_team_id"
    t.index ["user_id", "market", "subject_key"], name: "idx_on_user_id_market_subject_key_20a317c2fc", unique: true
    t.index ["user_id"], name: "index_outright_ledger_entries_on_user_id"
  end

  create_table "outright_picks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "market", null: false
    t.string "pick", null: false
    t.float "stake", default: 1.0, null: false
    t.string "subject_key", null: false
    t.string "subject_label", null: false
    t.integer "team_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["market", "subject_key"], name: "index_outright_picks_on_market_and_subject_key"
    t.index ["team_id"], name: "index_outright_picks_on_team_id"
    t.index ["user_id", "market", "subject_key"], name: "index_outright_picks_on_user_id_and_market_and_subject_key", unique: true
    t.index ["user_id"], name: "index_outright_picks_on_user_id"
  end

  create_table "poly_markets", force: :cascade do |t|
    t.boolean "closed", default: false, null: false
    t.string "condition_id"
    t.datetime "created_at", null: false
    t.string "event_id"
    t.integer "match_id", null: false
    t.string "match_method"
    t.float "match_score"
    t.string "slug"
    t.string "token_away"
    t.string "token_draw"
    t.string "token_home"
    t.datetime "updated_at", null: false
    t.float "volume"
    t.index ["match_id"], name: "index_poly_markets_on_match_id", unique: true
  end

  create_table "redemptions", force: :cascade do |t|
    t.float "cost", null: false
    t.datetime "created_at", null: false
    t.string "drink", null: false
    t.integer "qty", null: false
    t.float "unit_cost", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_redemptions_on_user_id"
  end

  create_table "settlements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.integer "match_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_settlements_on_created_by_id"
  end

  create_table "teams", force: :cascade do |t|
    t.json "aliases"
    t.string "code"
    t.string "confed"
    t.datetime "created_at", null: false
    t.string "flag"
    t.string "name", null: false
    t.string "name_zh"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "emoji"
    t.string "encrypted_password", default: "", null: false
    t.string "locale", default: "zh-CN", null: false
    t.string "nickname", null: false
    t.datetime "remember_created_at"
    t.string "remember_token"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "match_id", null: false
    t.string "pick", null: false
    t.float "stake", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["match_id", "user_id"], name: "index_votes_on_match_id_and_user_id", unique: true
    t.index ["match_id"], name: "index_votes_on_match_id"
    t.index ["user_id"], name: "index_votes_on_user_id"
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "goals", "matches"
  add_foreign_key "goals", "teams"
  add_foreign_key "ledger_entries", "matches"
  add_foreign_key "ledger_entries", "users"
  add_foreign_key "matches", "settlements"
  add_foreign_key "matches", "teams", column: "away_team_id"
  add_foreign_key "matches", "teams", column: "home_team_id"
  add_foreign_key "odds_snapshots", "matches"
  add_foreign_key "outright_candidates", "teams"
  add_foreign_key "outright_ledger_entries", "matches", column: "source_match_id"
  add_foreign_key "outright_ledger_entries", "teams"
  add_foreign_key "outright_ledger_entries", "users"
  add_foreign_key "outright_ledger_entries", "users", column: "settled_by_id"
  add_foreign_key "outright_picks", "teams"
  add_foreign_key "outright_picks", "users"
  add_foreign_key "poly_markets", "matches"
  add_foreign_key "redemptions", "users"
  add_foreign_key "settlements", "users", column: "created_by_id"
  add_foreign_key "votes", "matches"
  add_foreign_key "votes", "users"
end
