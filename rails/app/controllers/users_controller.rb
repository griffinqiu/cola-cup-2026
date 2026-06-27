class UsersController < ApplicationController
  before_action :require_login!

  def show
    @user = User.active.find(params[:id])
    @ledger = @user.ledger_entries
      .includes(match: [ :home_team, :away_team ]).references(:match)
      .order("matches.kickoff_at DESC")
    @outright_ledger = @user.outright_ledger_entries
      .includes(:team).order(settled_at: :desc, id: :desc)
    @redemptions = @user.redemptions.order(created_at: :desc, id: :desc)
    @wins = @ledger.count(&:won)
  end
end
