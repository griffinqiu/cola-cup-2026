module Admin
  class OddsSnapshotsController < BaseController
    # Manual odds entry — there is no UI for this in the panel, but the endpoint
    # is kept (legacy /api/admin/odds). Stores a non-locked "manual" snapshot.
    def create
      match = Match.find(params[:match_id])
      probabilities = parse_probabilities(match)
      unless probabilities
        return redirect_to(admin_settlements_path, alert: I18n.t("errors.odds.bad_probability"), status: :see_other)
      end

      match.odds_snapshots.create!(
        source: "manual", locked: false,
        p_home: probabilities[:home], p_draw: probabilities[:draw], p_away: probabilities[:away],
        d_home: DecimalOdds.price_to_decimal(probabilities[:home]),
        d_draw: probabilities[:draw] && DecimalOdds.price_to_decimal(probabilities[:draw]),
        d_away: DecimalOdds.price_to_decimal(probabilities[:away]),
        taken_at: Time.current
      )
      redirect_to admin_settlements_path, notice: I18n.t("flash.odds_updated"), status: :see_other
    end

    private

    def parse_probabilities(match)
      home = float_or_nil(params[:p_home])
      away = float_or_nil(params[:p_away])
      draw = match.allows_draw? ? float_or_nil(params[:p_draw]) : nil

      return nil unless in_range?(home) && in_range?(away)
      return nil if match.allows_draw? && !in_range?(draw)

      { home: home, draw: draw, away: away }
    end

    def float_or_nil(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def in_range?(value)
      value && value.finite? && value > 0 && value < 1
    end
  end
end
