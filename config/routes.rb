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

  # --- Admin panel (User::ADMIN_DISCORD_IDS only) ---
  namespace :admin do
    root "dashboard#index"

    # Solid Queue monitoring. Declared before the generic :model routes so
    # "jobs" isn't swallowed by them.
    get  "jobs",             to: "jobs#index",       as: :jobs
    post "jobs/retry_all",   to: "jobs#retry_all",   as: :jobs_retry_all
    post "jobs/discard_all", to: "jobs#discard_all", as: :jobs_discard_all
    post "jobs/:id/retry",   to: "jobs#retry_job",   as: :job_retry
    post "jobs/:id/discard", to: "jobs#discard_job", as: :job_discard

    # Generic read-only model browser: two catch-alls drive every model.
    get ":model",     to: "resources#index", as: :resources
    get ":model/:id", to: "resources#show",  as: :resource
  end

  # --- Dashboard (per-guild, tenant-scoped) ---
  resources :guilds, only: :show do
    post :recheck, on: :member
    # Curated roster lists (Manage Server only): directory categories and the
    # team-type vocabulary that teams pick from.
    resources :team_categories, only: %i[create update destroy]
    resources :team_types, only: %i[create update destroy]
    resources :teams, only: %i[new create show update] do
      resources :questions, only: %i[create update destroy], controller: "team_questions"
      resources :memberships, only: :show do
        post :remove, on: :member
        resources :notes, only: %i[create destroy], controller: "membership_notes"
        resources :applications, only: [], controller: "application_decisions" do
          member do
            post :accept
            post :reject
          end
        end
      end
    end
  end
end
