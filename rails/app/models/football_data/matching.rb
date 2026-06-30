module FootballData
  # Shared football-data payload helpers: map an external fixture onto one of
  # our matches via MatchIndex and orient its scores to our home/away sides.
  module Matching
    private

    # Returns [match_ref, fd_home_is_our_home] or [nil, nil] when unmatched.
    def locate_match(fd, index)
      home_name = fd.dig("homeTeam", "name")
      away_name = fd.dig("awayTeam", "name")
      home_id = home_name ? index.resolve_team(home_name) : nil
      away_id = away_name ? index.resolve_team(away_name) : nil
      return [ nil, nil ] if home_id.nil? || away_id.nil?

      match_ref = index.pair_match(home_id, away_id)
      return [ nil, nil ] if match_ref.nil?

      [ match_ref, home_id == match_ref[:home_id] ]
    end

    def our_scores(fd, fd_home_is_our_home)
      home, away = full_time_scores(fd)
      return [ nil, nil ] if home.nil? || away.nil?

      fd_home_is_our_home ? [ home, away ] : [ away, home ]
    end

    def full_time_scores(fd)
      full_time = fd.dig("score", "fullTime") || {}
      [ full_time["home"], full_time["away"] ]
    end

    # Our-perspective result for a FINISHED fixture: prefer football-data's
    # winner (covers ET/penalties), fall back to the full-time score.
    # fd_home_is_our_home maps their home/away to ours. nil when undecidable —
    # which for a knockout includes a level scoreline: a draw is impossible there,
    # so we return nil and wait for football-data to post the shootout winner
    # rather than freeze a premature "draw" (it briefly reports DRAW the instant a
    # penalty match goes FINISHED before backfilling the winner).
    def derive_result(fd, fd_home_is_our_home, knockout: false)
      case fd.dig("score", "winner")
      when "HOME_TEAM" then return fd_home_is_our_home ? "home" : "away"
      when "AWAY_TEAM" then return fd_home_is_our_home ? "away" : "home"
      when "DRAW" then return knockout ? nil : "draw"
      end

      home, away = full_time_scores(fd)
      return nil if home.nil? || away.nil?

      our_home = fd_home_is_our_home ? home : away
      our_away = fd_home_is_our_home ? away : home
      return "home" if our_home > our_away
      return "away" if our_home < our_away

      knockout ? nil : "draw"
    end
  end
end
