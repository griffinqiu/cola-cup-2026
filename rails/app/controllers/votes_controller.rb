class VotesController < ApplicationController
  include MatchDetailData

  before_action :require_login!
  before_action :set_match

  # Cast or change a prediction. The pick, the stake amount, and votability are
  # all validated server-side against the stage's allowed options. On success the
  # three personal/shared detail fragments re-render; the model's unique
  # (match_id, user_id) index makes a repeat vote an in-place update.
  def create
    pick = params[:pick].to_s
    stake = params[:stake].to_f
    return panel_error(I18n.t("errors.vote.bad_pick"), :unprocessable_content) unless @match.valid_picks.include?(pick)
    return panel_error(I18n.t("errors.vote.bad_stake"), :unprocessable_content) unless @match.valid_stake?(stake)
    return panel_error(I18n.t("errors.vote.not_votable"), :conflict) unless @match.votable?

    vote = Vote.find_or_initialize_by(match: @match, user: current_user)
    vote.update!(pick: pick, stake: stake)
    render_fragments
  end

  def destroy
    return panel_error(I18n.t("errors.vote.not_cancelable"), :conflict) unless @match.votable?

    Vote.where(match: @match, user: current_user).delete_all
    render_fragments
  end

  private

  def set_match
    @match = Match.find(params[:match_id])
  end

  def render_fragments(status: :ok)
    load_detail
    respond_to do |format|
      format.turbo_stream { render "votes/update", status: status }
      format.html { redirect_to match_path(@match), status: :see_other, alert: @error }
    end
  end

  def panel_error(message, status)
    @error = message
    render_fragments(status: status)
  end

  def load_detail
    @status = @match.status
    odds = @match.display_odds
    @market_odds = odds[:locked] || odds[:polymarket]
    @tally = @match.vote_tally
    @vote_odds = VoteOdds.from_tally(@tally, allows_draw: @match.allows_draw?)
    @votes = Vote.detailed_for(@match)
    @user_vote = current_user.votes.find_by(match_id: @match.id)
    @outcomes = helpers.match_outcomes(@match, @market_odds, @vote_odds)
    @polymarket_url = polymarket_url(@match)
    @next_match_id = next_match_id(@match)
  end
end
