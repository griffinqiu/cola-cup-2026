module Admin
  # The golden boot's final reveal is manual: it can only run once the final's
  # goals are synced (open_final! settles whoever's still unsettled — the top
  # scorer wins, the rest lose).
  class GoldenBootController < BaseController
    def open
      unless GoldenBoot.can_open_final?
        return redirect_to(admin_settlements_path, alert: I18n.t("flash.golden_boot_not_ready"), status: :see_other)
      end

      GoldenBoot.open_final!(settled_by: current_user)
      redirect_to admin_settlements_path, notice: I18n.t("flash.golden_boot_opened"), status: :see_other
    end
  end
end
