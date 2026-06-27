module Admin
  class SettlementsController < BaseController
    def index
      @todo = Match.settle_todo.includes(:home_team, :away_team)
      @tallies = Vote.tallies_by_match
      @records = Settlement.recent.includes(:matches)

      @outright_groups = OutrightLedgerEntry.includes(:user, :team, :settled_by)
        .order(settled_at: :desc, id: :desc).group_by(&:subject_key)
      @golden_boot_can_open = GoldenBoot.can_open_final?
      @golden_boot_pending = golden_boot_pending?
    end

    # Dry-run preview, rendered into the modal via Turbo Stream. Re-requested by
    # the preview_sheet Stimulus controller whenever the roster opt-in changes,
    # so every payout shown is recomputed server-side (single source of truth).
    def preview
      if selected_match_ids.empty?
        return redirect_to(admin_settlements_path, alert: "请选择要结算的比赛", status: :see_other)
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
        return redirect_to(admin_settlements_path, alert: "请选择要结算的比赛", status: :see_other)
      end

      result = Settlement.commit!(selected_match_ids, settler: current_user, included: included_param)
      redirect_to admin_settlements_path, notice: "已结算 #{result.settled} 场", status: :see_other
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

    # Golden boot is locked but some candidates are still unsettled, so the
    # final reveal button is worth showing.
    def golden_boot_pending?
      market = GoldenBoot::MARKET
      total = OutrightCandidate.for_market(market).count
      total.positive? && OutrightLedgerEntry.for_market(market).distinct.count(:subject_key) < total
    end
  end
end
