# Knockout ties decided on penalties carry a shootout score (e.g. 1:1, then 3:4
# on penalties). The level full-time score lives in home_score/away_score; these
# two columns hold the shootout digits, shown beside it. Openfootball's score.p
# supplies them going forward (Openfootball::ScheduleImport).
#
# Backfills + corrects the two Round-of-32 ties already played and on disk so they
# read "1–1（点 X:Y）" instead of a misleading scoreline:
#   m:74 德国 vs 巴拉圭 — football-data stored a stray 5:6; the real result is
#                         1:1, 点球 3:4 (Paraguay advanced 4-3 on penalties).
#   m:75 荷兰 vs 摩洛哥 — already corrected to 1:1 earlier; just add 点球 2:3.
# Only the DISPLAY moves: result, settled and the ledger are untouched — both ties
# settled on the right advancing side (away), so the cola already stands. update!
# (not record_result!) corrects the score and broadcasts it to open clients without
# re-settling. Each backfill is guarded on the resolved teams and is idempotent.
class AddPenaltyScoresToMatches < ActiveRecord::Migration[8.1]
  KNOWN_SHOOTOUTS = {
    "m:74" => { home: "Germany", away: "Paraguay", home_score: 1, away_score: 1, pen_home: 3, pen_away: 4 },
    "m:75" => { home: "Netherlands", away: "Morocco", home_score: 1, away_score: 1, pen_home: 2, pen_away: 3 }
  }.freeze

  def up
    add_column :matches, :pen_home, :integer
    add_column :matches, :pen_away, :integer
    Match.reset_column_information

    KNOWN_SHOOTOUTS.each do |external_key, shootout|
      match = Match.find_by(external_key: external_key)
      next say("#{external_key} not found — skipping penalty backfill") if match.nil?

      unless match.home_team&.name == shootout[:home] && match.away_team&.name == shootout[:away]
        next say(
          "#{external_key} is #{match.home_team&.name.inspect} vs #{match.away_team&.name.inspect}, " \
          "not #{shootout[:home]} vs #{shootout[:away]} — skipping"
        )
      end

      if match.home_score == shootout[:home_score] && match.away_score == shootout[:away_score] &&
         match.pen_home == shootout[:pen_home] && match.pen_away == shootout[:pen_away]
        next say("#{external_key} already shows the corrected score + shootout — skipping")
      end

      match.update!(
        home_score: shootout[:home_score], away_score: shootout[:away_score],
        pen_home: shootout[:pen_home], pen_away: shootout[:pen_away]
      )
      say(
        "#{external_key}: set #{shootout[:home_score]}:#{shootout[:away_score]} " \
        "点球 #{shootout[:pen_home]}:#{shootout[:pen_away]}"
      )
    end
  end

  def down
    remove_column :matches, :pen_away
    remove_column :matches, :pen_home
  end
end
