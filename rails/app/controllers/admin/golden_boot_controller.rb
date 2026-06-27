module Admin
  # The golden boot's final reveal is manual: it can only run once the final's
  # goals are synced (open_final! settles whoever's still unsettled — the top
  # scorer wins, the rest lose).
  class GoldenBootController < BaseController
    def open
      unless GoldenBoot.can_open_final?
        return redirect_to(admin_settlements_path, alert: "决赛尚未出结果，无法开奖", status: :see_other)
      end

      GoldenBoot.open_final!(settled_by: current_user)
      redirect_to admin_settlements_path, notice: "金靴奖已开奖", status: :see_other
    end
  end
end
