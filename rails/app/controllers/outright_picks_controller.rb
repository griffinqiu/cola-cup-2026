class OutrightPicksController < ApplicationController
  before_action :require_login!

  # Cast or change an outright pick. Market, side, stake bottles, votability and
  # the candidate are all validated server-side; the unique (user, market,
  # subject_key) index makes a repeat an in-place update.
  def create
    return reject("无效的玩法") unless OutrightPick::MARKETS.include?(market)
    return reject("无效的选项") unless OutrightPick::PICKS.include?(pick)
    return reject("无效的瓶数") unless OutrightPick::STAKE_OPTIONS.include?(stake)

    subject = find_subject
    return reject("该候选不可投注") unless subject
    return reject("该队已封盘，无法下注") unless Champion.open_for?(subject.team_id)

    record = current_user.outright_picks.find_or_initialize_by(market: market, subject_key: subject_key)
    record.update!(pick: pick, stake: stake,
                   subject_label: subject.subject_label, team_id: subject.team_id)
    render_card(subject)
  end

  def destroy
    subject = find_subject
    return reject("该队已封盘，无法撤销") unless subject && Champion.open_for?(subject.team_id)

    current_user.outright_picks.where(market: market, subject_key: subject_key).delete_all
    render_card(subject)
  end

  private

  def market
    @market ||= params[:market].to_s
  end

  def subject_key
    @subject_key ||= params[:subject_key].to_s
  end

  def pick
    @pick ||= params[:pick].to_s
  end

  def stake
    @stake ||= params[:stake].to_f
  end

  def find_subject
    OutrightBoard.driver(market).candidate_subjects.find { |subject| subject.subject_key == subject_key }
  end

  def render_card(subject)
    @row = OutrightBoard.new(market, current_user).row(subject)
    respond_to do |format|
      format.turbo_stream { render "outright_picks/update" }
      format.html { redirect_to predictions_path(tab: market), status: :see_other }
    end
  end

  def reject(message)
    redirect_to predictions_path(tab: market), alert: message, status: :see_other
  end
end
