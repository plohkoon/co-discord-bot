module BattleNet
  # Turns a completed Battle.net OAuth ceremony into a durable link: which
  # Blizzard account this Discord user owns, and which WoW characters Blizzard
  # confirms are theirs.
  #
  # This runs once per link, not on a schedule. The user token it rides in on
  # dies in 24 hours and can't be refreshed, so the job here is to capture
  # everything that only a user token can see — the character *roster* — and
  # leave. Ongoing refresh of any single character runs on the app token against
  # public endpoints (BattleNet::Client.app), which never expires.
  #
  # All HTTP happens before the transaction opens.
  class LinkAccount
    Result = Struct.new(:account, :characters, :error, keyword_init: true) do
      def ok? = error.nil?
    end

    # Probe order when we don't know where the user plays. Most users are
    # single-region, so the common case costs one request.
    REGION_ORDER = %w[us eu tw kr].freeze

    def self.call(...) = new(...).call

    # client_for: injectable for tests — ->(region) { BattleNet::Client }
    def initialize(user:, auth:, preferred_region: Client::DEFAULT_REGION, client_for: nil)
      @user = user
      @auth = auth
      @preferred_region = Client.region?(preferred_region) ? preferred_region.to_s : Client::DEFAULT_REGION
      @client_for = client_for || ->(region) { Client.for_user(token, region: region) }
    end

    def call
      return failure("Battle.net didn't return an account id.") if battle_net_id.blank?

      region, characters = discover_characters
      return failure("Couldn't reach Blizzard. Please try again.") if region.nil?

      persist(region, characters)
    rescue Client::Unauthorized
      failure("Blizzard rejected the authorization. Please try linking again.")
    rescue Client::Error => e
      Rails.logger.error("[web] Battle.net link failed for user #{@user.id}: #{e.class}: #{e.message}")
      failure("Couldn't read your Battle.net profile. Please try again.")
    end

    private

    def token = @auth.credentials&.token

    def battle_net_id
      @auth.uid.presence || @auth.extra&.raw_info&.dig("id")
    end

    def battle_tag
      @auth.info&.battletag.presence || @auth.extra&.raw_info&.dig("battletag")
    end

    # Ask each region for the user's WoW summary and take the first that knows
    # them. A Battle.net account with characters in two regions keeps only the
    # richer one — genuinely rare, and the alternative is a second account row
    # for one Blizzard id.
    def discover_characters
      reached = false
      best = nil

      regions.each do |region|
        characters = fetch_characters(region)
        next if characters.nil? # request failed — try the next region

        reached = true
        return [ region, characters ] if characters.any? && region == @preferred_region

        best = [ region, characters ] if best.nil? || characters.size > best[1].size
      end

      return [ nil, [] ] unless reached

      best || [ @preferred_region, [] ]
    end

    def regions = ([ @preferred_region ] + REGION_ORDER).uniq

    # nil means "couldn't ask"; [] means "asked, they have nothing here".
    def fetch_characters(region)
      payload = @client_for.call(region).wow_account_profile
      Array(payload&.dig("wow_accounts")).flat_map { |a| Array(a["characters"]) }
    rescue Client::NotFound
      [] # no WoW account in this region
    rescue Client::Unauthorized
      raise
    rescue Client::Error => e
      Rails.logger.warn("[web] Battle.net profile lookup failed in #{region}: #{e.message}")
      nil
    end

    def persist(region, characters)
      attributes = characters.filter_map { |c| character_attributes(c) }

      account = nil
      ActiveRecord::Base.transaction do
        account = @user.battle_net_accounts.find_or_initialize_by(battle_net_id: battle_net_id.to_i)
        account.battle_tag = battle_tag
        account.region = region
        account.linked_at = Time.current
        account.characters_synced_at = Time.current
        account.save!

        sync_characters(account, attributes)
      end

      Rails.logger.info("[web] linked Battle.net #{battle_tag} (#{region}) to user #{@user.id}: #{attributes.size} characters")
      # Fill in ilvl/spec/M+ in the background so the freshly linked characters
      # aren't blank until the hourly sweep comes round. Enqueued after the
      # transaction commits — the jobs read these rows.
      enqueue_refreshes(account)
      Result.new(account: account, characters: account.wow_characters.by_prominence.to_a)
    end

    def sync_characters(account, attributes)
      attributes.each do |attrs|
        # Looked up globally, not within this account: a character may already
        # exist as an unproven CLAIM — possibly someone else's. Blizzard saying
        # it's this user's outranks anyone's assertion, so verification takes
        # the row over rather than forking a duplicate.
        record = WowCharacter.find_or_initialize_by(blizzard_id: attrs[:blizzard_id])
        record.assign_attributes(attrs.merge(
          user: account.user,
          battle_net_account: account,
          region: account.region,
          # verified_at is set only here, where the data came back on the
          # owner's own token — that's the whole point of the ceremony.
          verified_at: Time.current
        ))
        record.save!
      end

      prune(account, attributes.map { |a| a[:blizzard_id] })
    end

    # Characters that vanished from Blizzard's list were deleted, or moved to
    # another Battle.net account. Either way this account no longer proves
    # anything about them.
    #
    # A character the user had independently *claimed* is demoted back to that
    # claim rather than deleted — losing the proof shouldn't also lose the
    # assertion, or their data would silently disappear from an application
    # they'd already submitted.
    # Queried by id rather than through account.wow_characters: sync_characters
    # creates rows via WowCharacter directly (it has to look them up globally),
    # so the association's cache never learns about them.
    def prune(account, keep)
      stale = WowCharacter.where(battle_net_account_id: account.id)
      stale = stale.where.not(blizzard_id: keep) if keep.any?

      stale.claimed.update_all(verified_at: nil, battle_net_account_id: nil, updated_at: Time.current)
      stale.where(claimed_at: nil).destroy_all
    end

    def enqueue_refreshes(account)
      account.wow_characters
             .refreshable(min_level: WowCharacterSweepJob::MIN_LEVEL)
             .by_prominence
             .pluck(:id)
             .each { |id| WowCharacterRefreshJob.perform_later(id) }
    end

    def character_attributes(raw)
      blizzard_id = raw["id"]
      realm = raw["realm"] || {}
      return nil if blizzard_id.blank? || raw["name"].blank? || realm["slug"].blank?

      {
        blizzard_id: blizzard_id.to_i,
        name: raw["name"].to_s,
        realm: localized(realm["name"]).presence || realm["slug"].to_s,
        realm_slug: realm["slug"].to_s,
        realm_id: realm["id"],
        level: raw["level"],
        playable_class: localized(raw.dig("playable_class", "name")),
        playable_race: localized(raw.dig("playable_race", "name")),
        faction: raw.dig("faction", "type")&.to_s&.downcase
      }
    end

    # We request locale=en_US so these come back as plain strings, but Blizzard
    # returns a {locale => value} object when a locale isn't honored.
    def localized(value)
      return value if value.is_a?(String)
      return value["en_US"] || value.values.first if value.is_a?(Hash)

      nil
    end

    def failure(message) = Result.new(account: nil, characters: [], error: message)
  end
end
