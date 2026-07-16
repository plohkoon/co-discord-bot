# Discord OAuth login. `identify` gets the user's account; `guilds` lets us list
# the servers they're in (to authorize per-guild access in the dashboard).
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :discord,
           ENV["DISCORD_CLIENT_ID"],
           ENV["DISCORD_CLIENT_SECRET"],
           scope: "identify guilds"
end

# Redirect to a friendly page instead of raising on OAuth failures.
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:failure).call(env)
end
