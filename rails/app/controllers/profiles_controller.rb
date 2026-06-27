class ProfilesController < ApplicationController
  before_action :require_login!

  def show
    @ledger = current_user.ledger_entries
      .includes(match: [ :home_team, :away_team ]).references(:match)
      .order("matches.kickoff_at DESC")
    @outright_ledger = current_user.outright_ledger_entries
      .includes(:team).order(settled_at: :desc, id: :desc)
    @total = current_user.ledger_entries.sum(:delta) + current_user.outright_ledger_entries.sum(:delta)
    @redeemed = current_user.redemptions.sum(:cost)
    @balance = @total - @redeemed
    @redemptions = current_user.redemptions.order(created_at: :desc, id: :desc)
    @wins = @ledger.count(&:won)
  end

  def edit
    @accounts = current_user.accounts
  end

  def update
    # New users land here right after first login (no emoji yet); on save they go
    # home, returning users stay on the ledger — mirrors the legacy ProfileForm.
    first_setup = current_user.emoji.nil?
    if current_user.update(profile_params)
      redirect_to(first_setup ? root_path : me_path, status: :see_other)
    else
      @accounts = current_user.accounts
      render :edit, status: :unprocessable_content
    end
  end

  private

  def profile_params
    { nickname: params[:nickname].to_s.strip, emoji: params[:emoji].presence }
  end
end
