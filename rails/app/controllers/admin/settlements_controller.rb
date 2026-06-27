module Admin
  class SettlementsController < BaseController
    def index
      @todo = Match.settle_todo.includes(:home_team, :away_team)
      @tallies = Vote.tallies_by_match
      @records = Settlement.recent.includes(:matches)
    end

    # Dry-run preview, rendered into the modal via Turbo Stream. Re-requested by
    # the preview_sheet Stimulus controller whenever the roster opt-in changes,
    # so every payout shown is recomputed server-side (single source of truth).
    def preview
      if selected_match_ids.empty?
        return redirect_to(admin_settlements_path, alert: I18n.t("flash.select_matches"), status: :see_other)
      end

      @included = included_param
      @preview = Settlement.preview(selected_match_ids, included: @included)
      @matches_by_id = Match.where(id: selected_match_ids).includes(:home_team, :away_team).index_by(&:id)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_settlements_path }
      end
    end

    def create
      if selected_match_ids.empty?
        return redirect_to(admin_settlements_path, alert: I18n.t("flash.select_matches"), status: :see_other)
      end

      result = Settlement.commit!(selected_match_ids, settler: current_user, included: included_param)
      redirect_to admin_settlements_path, notice: I18n.t("flash.settled", count: result.settled), status: :see_other
    rescue Settlement::CommitError => e
      redirect_to admin_settlements_path, alert: e.message, status: :see_other
    end

    private

    def selected_match_ids
      Array(params[:match_ids]).map(&:to_s)
    end

    # The per-match opt-in map { matchId => [userId, ...] }. Settler-only, so
    # to_unsafe_h is acceptable; Settlement.preview/commit re-validate the ids.
    def included_param
      raw = params[:included]
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : nil
    end
  end
end
