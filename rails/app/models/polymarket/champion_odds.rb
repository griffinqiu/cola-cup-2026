module Polymarket
  # Pulls Polymarket's standalone "World Cup Winner" market (one Yes/No market
  # per team) and caches each team's implied champion probability. Display-only,
  # exactly like the per-match moneyline odds — it never touches settlement,
  # which stays pure pari-mutuel on the actual 对/否 bottle pools.
  #
  # Team names resolve through the same MatchIndex (name + aliases, fuzzy token
  # subset) the moneyline matcher uses, so "France"/"IR Iran"/"USA" map cleanly.
  module ChampionOdds
    CACHE_KEY = "champion_odds/v1".freeze
    TTL = 6.hours
    WINNER_SLUG = "world-cup-winner".freeze
    MIN_PROB = 0.0005

    module_function

    # { team_id => probability(0..1) } from the last refresh; empty until then.
    def probabilities
      Rails.cache.read(CACHE_KEY) || {}
    end

    def refresh!
      event = fetch_event
      return {} unless event

      index = MatchIndex.build
      probs = {}
      Array(event["markets"]).each do |market|
        name = market["groupItemTitle"].presence || market["question"]
        prob = yes_price(market["outcomePrices"])
        next if name.blank? || prob.nil? || prob < MIN_PROB

        team_id = index.resolve_team(name)
        probs[team_id] = prob if team_id
      end

      Rails.cache.write(CACHE_KEY, probs, expires_in: TTL)
      probs
    end

    def fetch_event
      data = HttpJson.get("#{Sync::GAMMA}/events?slug=#{WINNER_SLUG}")
      events = data.is_a?(Array) ? data : Array(data["data"])
      events.find { |event| event["slug"] == WINNER_SLUG } || events.first
    end

    def yes_price(raw)
      parsed = begin
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        nil
      end
      parsed.is_a?(Array) && parsed[0] ? parsed[0].to_f : nil
    end
  end
end
