Rails.application.routes.draw do
  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard#index"
  get "install_status", to: "dashboard#install_status"

  # --- Auth ---
  get    "/login",  to: "sessions#new",     as: :login
  delete "/logout", to: "sessions#destroy", as: :logout
  # Discord OAuth (the login button POSTs to /auth/discord, handled by OmniAuth).
  get   "/auth/discord/callback", to: "sessions#create"
  match "/auth/failure",          to: "sessions#failure", via: %i[get post]

  # --- Dashboard (per-guild, tenant-scoped) ---
  resources :guilds, only: :show do
    post :recheck, on: :member
    resources :teams, only: %i[new create show update] do
      resources :questions, only: %i[create update destroy], controller: "team_questions"
      resources :memberships, only: :show do
        resources :notes, only: %i[create destroy], controller: "membership_notes"
      end
    end
  end
end
