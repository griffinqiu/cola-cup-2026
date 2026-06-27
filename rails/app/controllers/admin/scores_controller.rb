module Admin
  class ScoresController < BaseController
    def update
      match = Match.find(params[:match_id])
      home_score = score_param(:home_score)
      away_score = score_param(:away_score)

      if match.settled?
        match.update_display_score!(home_score: home_score, away_score: away_score)
      else
        match.record_result!(
          home_score: home_score, away_score: away_score,
          result: knockout_advancer(match, home_score, away_score)
        )
      end
      redirect_to admin_settlements_path, notice: I18n.t("flash.score_saved"), status: :see_other
    rescue Match::DomainError => e
      redirect_to admin_settlements_path, alert: e.message, status: :see_other
    end

    private

    def score_param(key)
      value = params[key]
      value.blank? ? nil : value.to_i
    end

    # Honour the submitted advancer only on a genuine knockout tie; otherwise the
    # result derives from the scoreline (forwarding it would override a decisive score).
    def knockout_advancer(match, home_score, away_score)
      return nil unless match.knockout? && home_score && away_score && home_score == away_score

      params[:result].presence
    end
  end
end
