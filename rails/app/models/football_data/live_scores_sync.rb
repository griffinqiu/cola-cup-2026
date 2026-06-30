module FootballData
  # The single live-window sync. Every minute it pulls the recent World Cup
  # fixtures and, in one pass, both refreshes in-play scores AND records the
  # final result the moment football-data marks a fixture FINISHED — recording
  # the result enqueues settlement (Match#record_result! → AutoSettleJob), so a
  # finished match flips to "settled" within a minute. In-play scores are
  # written without a result (record_live_score!), so a live score can never
  # settle a match early; only a FINISHED fixture writes the result. Skips the
  # API call entirely when no fixture is inside the live window.
  class LiveScoresSync
    include Matching

    BASE = "https://api.football-data.org/v4".freeze
    WORLD_CUP_CODE = "WC".freeze
    LIVE_STATUSES = %w[IN_PLAY PAUSED EXTRA_TIME PENALTY_SHOOTOUT].to_set.freeze
    FINISHED_STATUS = "FINISHED".freeze

    def self.run
      new.run
    end

    def run
      return idle unless Match.possibly_live.exists?

      key = ENV["FOOTBALL_DATA_API_KEY"]
      if key.blank?
        Rails.logger.info("[FootballData::LiveScoresSync] FOOTBALL_DATA_API_KEY not set — skipping.")
        return idle
      end

      today = Time.current.utc.to_date
      data = HttpJson.get(
        "#{BASE}/competitions/#{WORLD_CUP_CODE}/matches" \
        "?dateFrom=#{today - 2}&dateTo=#{today + 1}",
        headers: { "X-Auth-Token" => key }
      )
      index = MatchIndex.build

      counts = idle
      Array(data["matches"]).each do |fd|
        status = fd["status"]
        next unless LIVE_STATUSES.include?(status) || status == FINISHED_STATUS

        counts[sync_fixture(fd, index, status)] += 1
      end

      Rails.logger.info(
        "[FootballData::LiveScoresSync] live_updated=#{counts[:live_updated]} " \
        "results_recorded=#{counts[:results_recorded]} skipped=#{counts[:skipped]} " \
        "unmatched=#{counts[:unmatched]}"
      )
      counts
    end

    private

    # Maps one football-data fixture onto our match and applies it by status:
    # a live status refreshes the score only; FINISHED records the final result
    # (which enqueues settlement). Returns the tally key for this fixture.
    def sync_fixture(fd, index, status)
      match_ref, fd_home_is_our_home = locate_match(fd, index)
      return :unmatched if match_ref.nil?

      match = Match.find_by(id: match_ref[:match_id])
      return :skipped if match.nil?

      home_score, away_score = our_scores(fd, fd_home_is_our_home)

      if status == FINISHED_STATUS
        record_final_result(match, fd, fd_home_is_our_home, home_score, away_score)
      elsif match.record_live_score!(home_score: home_score, away_score: away_score)
        :live_updated
      else
        :skipped
      end
    rescue Match::DomainError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[FootballData::LiveScoresSync] skipped fixture: #{e.class}: #{e.message}")
      :skipped
    end

    # Records the final result for a FINISHED fixture. Skips when the match is
    # already settled, or already carries this exact result+score — so the
    # every-minute pull doesn't re-record (and re-enqueue settlement) while an
    # earlier AutoSettleJob is still in flight. A FINISHED payload occasionally
    # omits fullTime while still naming a winner; keep the live-phase score
    # rather than nulling it.
    def record_final_result(match, fd, fd_home_is_our_home, home_score, away_score)
      return :skipped if match.settled?

      result = derive_result(fd, fd_home_is_our_home, knockout: match.knockout?)
      return :skipped if result.nil?

      home_score = match.home_score if home_score.nil?
      away_score = match.away_score if away_score.nil?
      if match.result == result && match.home_score == home_score && match.away_score == away_score
        return :skipped
      end

      match.record_result!(home_score: home_score, away_score: away_score, result: result)
      :results_recorded
    end

    def idle
      { live_updated: 0, results_recorded: 0, skipped: 0, unmatched: 0 }
    end
  end
end
