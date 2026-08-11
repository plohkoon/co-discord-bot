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

  # --- Account settings (per-person, not guild-scoped) ---
  get "/account", to: "account#show", as: :account
  # Battle.net OAuth links a WoW account to the signed-in user; the "Link"
  # button POSTs to /auth/battle_net, handled by OmniAuth.
  get "/auth/battle_net/callback", to: "battle_net_accounts#create"
  # Claiming a character is deliberately separate from the Battle.net link —
  # it needs no OAuth and produces an unverified record.
  resources :wow_characters, only: %i[create destroy], path: "account/characters" do
    # Nominate a main. Explicit, and never overridden by inference afterwards.
    post :make_main, on: :member
  end
  resources :battle_net_accounts, only: :destroy, path: "account/battle-net" do
    # Re-pull ilvl / M+ from Blizzard's public endpoints. Needs no OAuth — the
    # app token does the work — so it stays available after the link expires.
    post :refresh, on: :member
  end

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
  resources :guilds, only: %i[show update] do
    post :recheck, on: :member
    # Curated roster lists (Manage Server only): directory categories and the
    # team-type vocabulary that teams pick from.
    resources :team_categories, only: %i[create update destroy]
    resources :team_types, only: %i[create update destroy]
    # WoW role rewards (Manage Server only): rules that grant a Discord role
    # from linked character data (achievements, M+ score, PvP rating).
    resources :role_rewards, only: %i[create destroy]
    # Absence call-outs — a lead cancels any on their team, a raider cancels
    # their own (from the guild page). Creating them happens in Discord.
    resources :absences, only: :destroy
    resources :teams, only: %i[new create show update] do
      resources :questions, only: %i[create update destroy], controller: "team_questions"
      resources :memberships, only: :show do
        post :remove, on: :member
        # Which character this member raids as on THIS team — a lead's call,
        # distinct from the member's own main.
        patch :character, on: :member, action: :set_character
        resources :notes, only: %i[create destroy], controller: "membership_notes"
        resources :applications, only: [], controller: "application_decisions" do
          member do
            post :accept
            post :reject
            # Park a pending application: no reminders, no 7-day auto-reject.
            post :pause
            post :resume
          end
        end
      end
    end
  end
end
