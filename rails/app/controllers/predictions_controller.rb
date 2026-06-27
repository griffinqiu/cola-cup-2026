class PredictionsController < ApplicationController
  # Both outright markets live under one tab; ?tab= picks the sub-page. Viewable
  # signed-out (like the schedule); only casting a pick requires login.
  def index
    @tab = OutrightPick::MARKETS.include?(params[:tab]) ? params[:tab] : Champion::MARKET
    # Live as soon as the first round-of-16 team is known; each team then locks
    # 1h before its own match (per-card), so there's no single global deadline.
    @available = Champion.available?

    if current_user
      @my_bottles = current_user.outright_picks.sum(:stake)
      @my_pick_count = current_user.outright_picks.count
      # Backing several candidates to win (押"对") spreads you thin — only one
      # team/player can take the title, so most of those bets must lose.
      @yes_count = current_user.outright_picks.where(market: @tab, pick: "yes").count
    end

    @rows = OutrightBoard.new(@tab, current_user).rows
  end
end
