Rails.application.routes.draw do
  devise_for :users,
    skip: [ :sessions, :registrations, :passwords ],
    controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  devise_scope :user do
    delete "/logout", to: "users/sessions#destroy", as: :destroy_user_session
  end

  root "matches#index"
  resources :matches, only: [ :show ] do
    resource :vote, only: [ :create, :destroy ]
  end

  resources :teams, only: [ :show ]
  get "/groups", to: "groups#index", as: :groups
  get "/groups/:letter", to: "groups#show", as: :group, constraints: { letter: /[A-L]/ }
  get "/third-place", to: "standings#third_place", as: :third_place
  get "/scorers", to: "scorers#index", as: :scorers

  get "/leaderboard", to: "leaderboards#show", as: :leaderboard
  resources :users, only: [ :show ]
  get "/me", to: "profiles#show", as: :me
  get "/me/settings", to: "profiles#edit", as: :me_settings
  patch "/me/settings", to: "profiles#update"
  resources :redemptions, only: [ :create ]

  patch "/locale", to: "locales#update", as: :locale

  get "/identity", to: "identities#show", as: :identity
  get "/about", to: "pages#about", as: :about
  get "/auth/error", to: "auth_errors#show", as: :auth_error

  namespace :admin do
    root to: "settlements#index"
    resources :settlements, only: [ :index, :create ] do
      post :preview, on: :collection
    end
    resources :matches, only: [] do
      resource :score, only: [ :update ]
      resources :odds_snapshots, only: [ :create ]
    end
    resources :users, only: [ :index, :destroy ] do
      patch :restore, on: :member
    end
  end

  # Solid Queue dashboard — gated by Admin::BaseController (settlers only).
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  get "up" => "rails/health#show", as: :rails_health_check
end
