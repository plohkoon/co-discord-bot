namespace :co_bot do
  desc "Resolve pending applications stranded on non-pending memberships: system-reject on archived ones " \
       "(they block re-applying via the one-pending-per-user index), system-accept on active ones (a manual " \
       "role grant was the acceptance). Re-runs Archive/Activate, which also repaint review messages. " \
       "Safe to re-run anytime (idempotent)."
  task cleanup_stranded_applications: :environment do
    Guild.find_each do |guild|
      ActsAsTenant.with_tenant(guild) do
        stranded = TeamMembership.where.not(status: :pending)
                                 .joins(:team_applications).merge(TeamApplication.pending).distinct
        stranded.find_each do |membership|
          if membership.archived?
            Memberships::Archive.call(membership)
            verb = "rejected"
          else
            Memberships::Activate.call(team: membership.team, discord_user_id: membership.discord_user_id,
                                       username: membership.discord_username)
            verb = "accepted"
          end
          puts "#{guild.name} / #{membership.team.name}: #{verb} stranded application for " \
               "#{membership.discord_username} (#{membership.discord_user_id})"
        end
      end
    end
  end

  desc "Re-seed every team's members + officers mirrors from Discord (REST sweep), then reflow rosters. " \
       "Run once after a deploy that adds mirror tables; safe to re-run anytime (idempotent)."
  task backfill: :environment do
    Guild.installed.find_each do |guild|
      ActsAsTenant.with_tenant(guild) do
        Team.active.find_each do |team|
          count = Memberships::Backfill.call(team: team)
          puts "#{guild.name} / #{team.name}: #{count} member(s), #{team.team_officers.count} officer(s)"
        rescue Discord::BotApi::Error => e
          puts "#{guild.name} / #{team.name}: FAILED (#{e.class}: #{e.message})"
        end
      end

      RosterRefreshJob.perform_now(guild_id: guild.id)
      puts "#{guild.name}: roster reflowed"
    end
  end

  desc "Dump the shape of wowaudit's API responses (keys and value types, never values) so an " \
       "endpoint can be wired up without guessing. wowaudit publishes no machine-readable spec. " \
       "Usage: bin/rails co_bot:wowaudit_probe KEY=<your wowaudit API key> [PATH=/characters]"
  task wowaudit_probe: :environment do
    key = ENV["KEY"].to_s.strip
    if key.blank?
      puts "Set KEY=<your wowaudit API key> (wowaudit > your team > settings > API; team admins only)."
      next
    end

    client = WowAudit::Client.new(api_key: key)
    paths = ENV["PATH_"].presence ? [ ENV["PATH_"] ] : %w[/team /characters /period /raids]

    paths.each do |path|
      puts "\nGET /v1#{path}"
      puts describe_shape(client.get(path)).join("\n")
    rescue WowAudit::Client::Unauthorized
      puts "  401 — the key was rejected. wowaudit answers identically for a wrong, malformed, or"
      puts "  absent key, so this only tells you it isn't working, not why."
    rescue WowAudit::Client::Error => e
      puts "  #{e.class}: #{e.message}"
    end
  end

  # Keys and value types only — a roster is other people's data and has no
  # business in a terminal scrollback.
  def describe_shape(value, indent = "  ", depth = 0)
    return [ "#{indent}(nothing)" ] if value.nil?
    return [ "#{indent}..." ] if depth > 3

    case value
    when Hash
      value.flat_map do |k, v|
        case v
        when Hash, Array then [ "#{indent}#{k}: #{v.class.name.downcase}" ] + describe_shape(v, "#{indent}  ", depth + 1)
        else "#{indent}#{k}: #{v.class.name.downcase}"
        end
      end
    when Array
      return [ "#{indent}(empty array)" ] if value.empty?

      [ "#{indent}array[#{value.size}], first item:" ] + describe_shape(value.first, "#{indent}  ", depth + 1)
    else [ "#{indent}#{value.class.name.downcase}" ]
    end
  end

  desc "Check the Warcraft Logs credentials end to end and dump the parts of the response this app " \
       "actually parses. Built from the published v2 schema without credentials to hand, so the " \
       "PARSING is the unverified half. Usage: bin/rails co_bot:warcraft_logs_check [CHARACTER=Name-Realm]"
  task warcraft_logs_check: :environment do
    unless WarcraftLogs::Client.configured?
      puts "WARCRAFTLOGS_CLIENT_ID / WARCRAFTLOGS_CLIENT_SECRET are not set."
      puts "Create a v2 client at https://www.warcraftlogs.com/api/clients/ — no redirect URI needed;"
      puts "this only ever uses the client-credentials grant."
      next
    end

    id = WarcraftLogs::Client.client_id
    puts "WARCRAFTLOGS_CLIENT_ID  #{id[0, 8]}… (#{id.length} chars)"

    begin
      WarcraftLogs::Client.expire_access_token
      WarcraftLogs::Client.access_token
      puts "token ................. OK"
    rescue => e
      puts "token ................. FAILED (#{e.class}: #{e.message})"
      next
    end

    client = WarcraftLogs::Client.new

    limits = client.rate_limit
    puts "rate limit ............ #{limits["pointsSpentThisHour"]} of #{limits["limitPerHour"]} points " \
         "spent, resets in #{limits["pointsResetIn"]}s"

    zones = client.zones
    closed = zones.count { |z| z["frozen"] }
    puts "zones ................. #{zones.size} (#{closed} frozen/closed)"
    live = zones.reject { |z| z["frozen"] }.max_by { |z| z["id"].to_i }
    puts "newest live zone ...... #{live&.dig("name").inspect} (id #{live&.dig("id")})"
    journal = Array(live&.dig("encounters")).count { |e| e["journalID"].to_i.positive? }
    puts "  encounters with a journalID: #{journal} of #{Array(live&.dig("encounters")).size}"
    puts "  (journalID is what joins these tiers to Raider.io — see WowEncounter)"

    name, realm = (ENV["CHARACTER"] || default_wcl_character).to_s.split("-", 2)
    if name.blank? || realm.blank?
      puts "\nSet CHARACTER=Name-Realm to verify the ranking parse against a real raider."
      next
    end

    puts "\nzoneRankings for #{name}-#{realm} in #{live&.dig("name")}:"
    payload = client.character_zone_rankings(
      name: name, server_slug: realm.downcase.tr(" ", "-"), region: "us", zone_id: live&.dig("id")
    )
    rankings = payload["zoneRankings"]
    if rankings.blank?
      puts "  (character exists on Warcraft Logs but has no parses in this tier)"
      next
    end

    # These four are exactly the assumptions RefreshCharacter makes.
    puts "  difficulty ................. #{rankings["difficulty"].inspect}"
    puts "  bestPerformanceAverage ..... #{rankings["bestPerformanceAverage"].inspect}"
    puts "  medianPerformanceAverage ... #{rankings["medianPerformanceAverage"].inspect}"
    puts "  allStars is an Array? ...... #{rankings["allStars"].class} " \
         "#{Array(rankings["allStars"]).first&.keys.inspect}"
    per_encounter = Array(rankings["rankings"])
    puts "  rankings[] ................. #{per_encounter.size} encounters, " \
         "totalKills sums to #{per_encounter.sum { |e| e["totalKills"].to_i }}"
    puts "  keys present ............... #{rankings.keys.sort.inspect}"
  end

  # Any linked character is a better probe than a hardcoded stranger.
  def default_wcl_character
    WowCharacter.where(level: 70..).by_prominence.first&.then { |c| "#{c.name}-#{c.realm}" }
  end

  desc "Print the exact Battle.net OAuth request this app will send, so it can be diffed against the " \
       "Redirect URIs field in the Blizzard portal. Blizzard matches redirect_uri by exact string and " \
       "reports every mismatch as the same unhelpful 400."
  task battle_net_oauth_check: :environment do
    id = ENV["BLIZZARD_CLIENT_ID"].to_s
    secret = ENV["BLIZZARD_CLIENT_SECRET"].to_s
    origin = ENV["APP_URL"].presence&.chomp("/") || "http://localhost:3000"
    redirect_uri = "#{origin}/auth/battle_net/callback"
    scope = OmniAuth::Strategies::BattleNet.default_options.dig("scope") ||
            OmniAuth::Strategies::BattleNet.default_options[:scope]

    puts "BLIZZARD_CLIENT_ID      #{id.presence ? "#{id[0, 8]}… (#{id.length} chars)" : "(not set)"}"
    puts "BLIZZARD_CLIENT_SECRET  #{secret.presence ? "set (#{secret.length} chars)" : "(not set)"}"
    puts "APP_URL                 #{ENV["APP_URL"].presence || "(not set — using http://localhost:3000)"}"
    puts
    puts "Register this EXACTLY in the portal's Redirect URIs field:"
    puts "  #{redirect_uri}"
    puts
    puts "Authorize URL this app will send you to:"
    puts "  https://oauth.battle.net/authorize?client_id=#{id}" \
         "&redirect_uri=#{CGI.escape(redirect_uri)}&response_type=code&scope=#{CGI.escape(scope.to_s)}&state=CHECK"
    puts
    puts "Reading Blizzard's reply (measured, not guessed):"
    puts "  /authorize validates almost nothing up front — an unregistered redirect_uri, an openid"
    puts "  scope, even response_type=token all get a 302 to the login page. So a green light here"
    puts "  means nothing."
    puts "  401 Bad client credentials .................. client_id is wrong or from another app"
    puts "  400 redirect_uri must be a valid URI ........ redirect_uri missing or malformed"
    puts "  400 Invalid grant type or callback URL ...... shown AFTER you log in. Blizzard compares"
    puts "      redirect_uri to the client's registered list only at that point, so this always means"
    puts "      a real mismatch: the string above is not registered on THIS client id."

    if BattleNet::Client.configured?
      begin
        BattleNet::Client.expire_app_token
        BattleNet::Client.app_token
        puts "\nclient-credentials token: OK — the id/secret pair is valid."
      rescue => e
        puts "\nclient-credentials token: FAILED (#{e.message}) — the id/secret pair itself is wrong."
      end
    end
  end
end
