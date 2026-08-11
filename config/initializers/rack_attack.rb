# Application-wide request throttling (Rack::Attack).
#
# Store: a plain in-memory MemoryStore. The app runs as a SINGLE Puma process
# (no `workers` / WEB_CONCURRENCY — see config/puma.rb), so one process-wide,
# thread-safe counter map is all the throttles need; nothing has to be shared
# across processes or survive a restart. If this ever scales to multiple Puma
# workers or instances, switch this to a shared store (e.g. :solid_cache_store)
# so the counters are pooled — the throttle rules below stay the same.
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Throttles key on `req.ip`. Rack::Attack is appended after
# ActionDispatch::RemoteIp, so `req.ip` is the client address Rails computed
# from X-Forwarded-For (behind Fly's proxy this is the real visitor, provided
# trusted_proxies stays correct), not the edge IP.

# The abuse vector the security review flagged: the public apply POST is
# reachable by any signed-in Discord account, guild slugs are enumerable, and
# each submit pings a team's officer channel + spends a Blizzard call. Keying
# on IP (not the user id, as the earlier per-controller limit did) also catches
# an attacker rotating throwaway accounts from one host. A human applies to a
# handful of teams; 5/min is generous for that, punishing for a script.
Rack::Attack.throttle("apply/ip", limit: 5, period: 60) do |req|
  req.ip if req.post? && req.path.match?(%r{\A/apply/[^/]+/teams/[^/]+/applications\z})
end

# Sign-in is the other unauthenticated write. Loose enough to never bother a
# real person retrying a cancelled OAuth, tight enough to stop hammering.
Rack::Attack.throttle("login/ip", limit: 15, period: 60) do |req|
  req.ip if req.post? && req.path == "/auth/discord"
end

# A blanket safety net against pure flooding (incl. anonymous slug enumeration
# over GET). Deliberately generous — a browsing human never approaches it.
Rack::Attack.throttle("req/ip", limit: 300, period: 60) do |req|
  req.ip
end

# Throttled requests get a clean 429 with a Retry-After, not a bare Rack error.
Rack::Attack.throttled_responder = lambda do |req|
  retry_after = (req.env["rack.attack.match_data"] || {})[:period]
  body = "You're doing that too fast. Please wait a moment and try again."
  [ 429,
    { "Content-Type" => "text/plain; charset=utf-8", "Retry-After" => retry_after.to_s },
    [ body ] ]
end

# The suite makes far more than 300 requests/min from 127.0.0.1, which would
# trip these and flake unrelated tests. Off by default in test; the throttle
# test flips it on (and calls Rack::Attack.reset!) for its own assertions.
Rack::Attack.enabled = false if Rails.env.test?
