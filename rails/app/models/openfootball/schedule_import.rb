require "time"

module Openfootball
  # Imports teams + the full fixture list from openfootball. Ported from
  # src/lib/jobs/importSchedule.ts. Idempotent upsert keyed on team name /
  # match external_key, so re-running refreshes data without creating rows.
  #
  # Source `:network` fetches live JSON (used by ImportScheduleJob); `:vendor`
  # reads the JSON checked into db/data/openfootball (used by db/seeds.rb so the
  # initial seed works offline).
  class ScheduleImport
    BASE = "https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026".freeze
    TEAMS_URL = "#{BASE}/worldcup.teams.json".freeze
    SCHEDULE_URL = "#{BASE}/worldcup.json".freeze
    VENDOR_DIR = Rails.root.join("db/data/openfootball")

    ZH_NAMES = {
      "Algeria" => "阿尔及利亚",
      "Argentina" => "阿根廷",
      "Australia" => "澳大利亚",
      "Austria" => "奥地利",
      "Belgium" => "比利时",
      "Bosnia & Herzegovina" => "波黑",
      "Bosnia and Herzegovina" => "波黑",
      "Brazil" => "巴西",
      "Canada" => "加拿大",
      "Cape Verde" => "佛得角",
      "Colombia" => "哥伦比亚",
      "Croatia" => "克罗地亚",
      "Curaçao" => "库拉索",
      "Czech Republic" => "捷克",
      "Czechia" => "捷克",
      "DR Congo" => "刚果（金）",
      "Ecuador" => "厄瓜多尔",
      "Egypt" => "埃及",
      "England" => "英格兰",
      "France" => "法国",
      "Germany" => "德国",
      "Ghana" => "加纳",
      "Haiti" => "海地",
      "Iran" => "伊朗",
      "Iraq" => "伊拉克",
      "Ivory Coast" => "科特迪瓦",
      "Japan" => "日本",
      "Jordan" => "约旦",
      "Mexico" => "墨西哥",
      "Morocco" => "摩洛哥",
      "Netherlands" => "荷兰",
      "New Zealand" => "新西兰",
      "Norway" => "挪威",
      "Panama" => "巴拿马",
      "Paraguay" => "巴拉圭",
      "Portugal" => "葡萄牙",
      "Qatar" => "卡塔尔",
      "Saudi Arabia" => "沙特阿拉伯",
      "Scotland" => "苏格兰",
      "Senegal" => "塞内加尔",
      "South Africa" => "南非",
      "South Korea" => "韩国",
      "Spain" => "西班牙",
      "Sweden" => "瑞典",
      "Switzerland" => "瑞士",
      "Tunisia" => "突尼斯",
      "Turkey" => "土耳其",
      "USA" => "美国",
      "Uruguay" => "乌拉圭",
      "Uzbekistan" => "乌兹别克斯坦"
    }.freeze

    ROUND_TO_STAGE = {
      "Round of 32" => "r32",
      "Round of 16" => "r16",
      "Quarter-final" => "qf",
      "Semi-final" => "sf",
      "Match for third place" => "third",
      "Final" => "final"
    }.freeze

    def self.run(source: :network)
      new(source: source).run
    end

    def initialize(source: :network)
      @source = source
    end

    def run
      teams = load_json(:teams)
      schedule = load_json(:schedule)
      matches = Array(schedule["matches"])

      import_teams(teams)
      import_matches(matches)

      { teams: teams.size, matches: matches.size }
    end

    private

    def load_json(kind)
      if @source == :vendor
        file = kind == :teams ? "worldcup.teams.json" : "worldcup.json"
        JSON.parse(File.read(VENDOR_DIR.join(file)))
      else
        HttpJson.get(kind == :teams ? TEAMS_URL : SCHEDULE_URL)
      end
    end

    def import_teams(teams)
      ActiveRecord::Base.transaction do
        teams.each do |team|
          name = team["name"]
          Team.find_or_initialize_by(name: name).update!(
            code: team["fifa_code"],
            name_zh: ZH_NAMES[name] || team["name_normalised"] || name,
            flag: team["flag_icon"],
            confed: team["confed"],
            aliases: team_aliases(team)
          )
        end
      end
    end

    def import_matches(matches)
      name_to_id = Team.pluck(:name, :id).to_h
      ActiveRecord::Base.transaction do
        matches.each do |match|
          record = Match.find_or_initialize_by(external_key: external_key(match))
          home_id = merged_team_id(record, :home_team_id, name_to_id[match["team1"]])
          away_id = merged_team_id(record, :away_team_id, name_to_id[match["team2"]])
          record.update!(
            group_name: match["group"],
            stage: map_stage(match["round"]),
            home_team_id: home_id,
            away_team_id: away_id,
            home_label: home_id ? nil : match["team1"],
            away_label: away_id ? nil : match["team2"],
            venue: match["ground"],
            kickoff_at: parse_kickoff(match["date"], match["time"])
          )
          sync_goals(record, match, home_id, away_id) if match.key?("score")
        end
      end
    end

    # Openfootball is the fallback for knockout matchups, never the authority: once a
    # slot is resolved locally (KnockoutResolver) or by an earlier import, keep that
    # team rather than letting a still-placeholder upstream row clear it back to nil.
    # Group matches always carry real teams upstream, so incoming is never nil there.
    def merged_team_id(record, attribute, incoming_id)
      incoming_id || record.public_send(attribute)
    end

    # openfootball lists goalscorers per side once a match is played: goals1
    # belongs to team1 (our home), goals2 to team2 (our away). We deliberately
    # never write the match score here — football-data.org owns home_score /
    # away_score / result — only the goal events that feed the top-scorer board.
    # Own goals are kept flagged so the board can exclude them from a player's
    # tally. Goals are replaced wholesale per match so re-runs and upstream
    # corrections stay idempotent.
    def sync_goals(record, match, home_id, away_id)
      record.goals.delete_all
      rows = goal_rows(match["goals1"], home_id) + goal_rows(match["goals2"], away_id)
      return if rows.empty?

      Goal.insert_all(rows.map { |row| row.merge(match_id: record.id) })
    end

    def goal_rows(goals, team_id)
      now = Time.current
      Array(goals).filter_map do |goal|
        name = goal["name"]
        next if name.blank?

        {
          team_id: team_id,
          player_name: name,
          minute: goal["minute"]&.to_i,
          penalty: goal["penalty"] == true,
          own_goal: goal["owngoal"] == true,
          created_at: now,
          updated_at: now
        }
      end
    end

    def team_aliases(team)
      aliases = []
      normalised = team["name_normalised"]
      aliases << normalised if normalised.present? && normalised != team["name"]
      aliases << team["fifa_code"] if team["fifa_code"].present?
      aliases
    end

    # Stable identity for idempotent re-import. Knockout slots carry a fixed
    # `num` (73, 74, …) that survives "2A" → real-team resolution; group matches
    # have fixed teams, so a team-based key is stable for them.
    def external_key(match)
      if match["num"]
        "m:#{match["num"]}"
      else
        "#{match["round"]}|#{match["date"]}|#{match["team1"]}|#{match["team2"]}"
      end
    end

    def map_stage(round)
      return "group" if round.to_s.start_with?("Matchday")

      ROUND_TO_STAGE[round] || "group"
    end

    # openfootball time looks like "13:00 UTC-6"; convert to an absolute instant.
    def parse_kickoff(date, time)
      hour_minute, zone = time.to_s.strip.split(/\s+/, 2)
      offset = "+00:00"
      if zone && (matched = zone.match(/UTC([+-])(\d{1,2})(?::?(\d{2}))?/))
        offset = format("%s%02d:%02d", matched[1], matched[2].to_i, (matched[3] || 0).to_i)
      end
      Time.iso8601("#{date}T#{hour_minute}:00#{offset}")
    rescue ArgumentError
      raise "Unable to parse kickoff: #{date.inspect} #{time.inspect}"
    end
  end
end
