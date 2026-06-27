module Broadcasts
  # Shared broadcast fragments. The partials are the same files the pages render
  # initially; locals are explicit and never reference current_user (per-viewer
  # state is handled by the viewer's own response or by client-side Stimulus).
  #
  # Every stream is per-locale: a fragment is rendered once per supported locale
  # and pushed to a locale-suffixed stream (e.g. ["schedule", :en]), matching the
  # views' `turbo_stream_from "...", I18n.locale` subscriptions. Without this a
  # single zh-CN fragment would land on every viewer regardless of language.
  module Renderable
    POLYMARKET_EVENT_BASE = "https://polymarket.com/event/".freeze

    private

    # Render a fragment once per supported locale, with I18n.locale set so the
    # partial's t()/display_name/format_* resolve in that language.
    def each_locale
      User::LOCALES.each { |locale| I18n.with_locale(locale) { yield locale } }
    end

    # Fan a locale-agnostic page-refresh signal out to every locale stream, so
    # subscribers on locale-suffixed streams receive it (the client re-GETs the
    # page and re-localizes itself). No rendering, so no with_locale needed.
    def broadcast_refresh_each_locale(*streamables)
      User::LOCALES.each { |locale| Turbo::StreamsChannel.broadcast_refresh_to(*streamables, locale) }
    end

    def find_match(match_id)
      Match.includes(:home_team, :away_team).find_by(id: match_id)
    end

    def broadcast_odds_compare(match)
      vote_odds = match.current_vote_odds
      market = market_snapshot(match)
      polymarket_url = polymarket_url(match)
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          "match", match, locale,
          target: "odds_compare_#{match.id}",
          partial: "matches/odds_compare",
          locals: {
            match: match,
            outcomes: ApplicationController.helpers.match_outcomes(match, market, vote_odds),
            low_sample: vote_odds&.low_sample?,
            polymarket_url: polymarket_url,
            market_snapshot: market
          }
        )
      end
    end

    def broadcast_votes_list(match)
      votes = Vote.detailed_for(match)
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          "match", match, locale,
          target: "votes_list_#{match.id}",
          partial: "matches/votes_list",
          locals: { match: match, votes: votes }
        )
      end
    end

    def broadcast_card_big(match)
      tally = match.vote_tally
      market = market_snapshot(match)
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          "schedule", locale,
          target: "match_card_big_#{match.id}",
          partial: "matches/card_big",
          locals: { match: match, tally: tally, market: market }
        )
      end
    end

    def broadcast_card_teams(match)
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          "schedule", locale,
          target: "match_card_teams_#{match.id}",
          partial: "matches/card_teams",
          locals: { match: match }
        )
      end
    end

    def broadcast_card_meta(match)
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          "schedule", locale,
          target: "match_card_meta_#{match.id}",
          partial: "matches/card_meta",
          locals: { match: match, voted: false }
        )
      end
    end

    def broadcast_leaderboard
      entries = User.leaderboard
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          "leaderboard", locale,
          target: "leaderboard_rows",
          partial: "leaderboards/board",
          locals: { entries: entries }
        )
      end
    end

    def market_snapshot(match)
      odds = match.display_odds
      odds[:locked] || odds[:polymarket]
    end

    def polymarket_url(match)
      slug = match.poly_market&.slug
      slug.present? ? "#{POLYMARKET_EVENT_BASE}#{slug}" : nil
    end
  end
end
