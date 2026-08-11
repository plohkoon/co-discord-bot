require Rails.root.join("lib/omniauth/strategies/battle_net")

# Discord OAuth login. `identify` gets the user's account; `guilds` lets us list
# the servers they're in (to authorize per-guild access in the dashboard);
# `connections` surfaces third-party accounts they've already linked to Discord
# — notably Battle.net, which gives us their BattleTag for free (see
# Discord::Connections). Widening the scope makes Discord re-prompt existing
# users for consent on their next sign-in, which is expected.
#
# Battle.net OAuth is a *separate, opt-in* link, not a login: it proves which
# WoW characters a user actually owns. See lib/omniauth/strategies/battle_net.rb.
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :discord,
           ENV["DISCORD_CLIENT_ID"],
           ENV["DISCORD_CLIENT_SECRET"],
           scope: "identify guilds connections"

  provider :battle_net,
           ENV["BLIZZARD_CLIENT_ID"],
           ENV["BLIZZARD_CLIENT_SECRET"]
end

# Blizzard validates redirect_uri by exact string match, so the callback URL has
# to be stable no matter how the request arrived. Set APP_URL when this app is
# reached at a different origin than the inbound request host — behind a tunnel
# (ngrok/cloudflared) or a TLS proxy — and OmniAuth builds every callback from
# it instead of from the request.
#
#   APP_URL=https://co-bot.ngrok.app
#
# Unset (plain localhost, and production where the request host is already
# right) leaves OmniAuth's default behaviour untouched.
if ENV["APP_URL"].present?
  OmniAuth.config.full_host = ENV["APP_URL"].chomp("/")
end

# Redirect to a friendly page instead of raising on OAuth failures. The Discord
# strategy fails a *login*; Battle.net fails an account *link* on an already
# signed-in session, so they land in different places.
OmniAuth.config.on_failure = proc do |env|
  if env["omniauth.error.strategy"]&.name.to_s == "battle_net"
    BattleNetAccountsController.action(:failure).call(env)
  else
    SessionsController.action(:failure).call(env)
  end
end
