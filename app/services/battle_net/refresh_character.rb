module BattleNet
  # Pull one character's live data from Blizzard's public profile endpoints.
  #
  # This is the half of the WoW integration that runs forever: it uses the app's
  # client-credentials token (BattleNet::Client.app), never a user token, so it
  # keeps working long after the 24h link ceremony expired. Everything it needs
  # — region, realm slug, name — was captured at link time.
  #
  # Two requests per character: the profile (ilvl, spec, guild, last login) and
  # the mythic keystone profile (current-season M+ rating). The second is
  # optional by design — Blizzard 404s it for anyone who hasn't run a key this
  # season, which is not an error.
  class RefreshCharacter
    # :refreshed — data updated
    # :missing   — Blizzard doesn't know this character any more
    # :failed    — transient; the caller should retry
    Result = Struct.new(:character, :status, :error, keyword_init: true) do
      def ok? = status == :refreshed
    end

    def self.call(...) = new(...).call

    def initialize(character, client: nil)
      @character = character
      @client = client
    end

    def call
      profile = client.character_profile(@character.realm_slug, @character.name)
      @character.update!(attributes_from(profile).merge(
        mythic_rating: mythic_rating,
        refreshed_at: Time.current,
        missing_at: nil # a successful read clears a previous disappearance
      ))
      Result.new(character: @character, status: :refreshed)
    rescue Client::NotFound
      # Deleted, renamed, or transferred. Keep the last known data (it's still
      # the best we have) and stamp it so the sweep stops hammering the endpoint.
      @character.update!(missing_at: Time.current, refreshed_at: Time.current)
      Result.new(character: @character, status: :missing)
    end

    private

    def client = @client ||= Client.app(region: @character.region)

    def attributes_from(profile)
      {
        # Blizzard's own spelling of these can drift from what the account
        # summary gave us at link time (renames aside, a race change is real).
        name: profile["name"].presence || @character.name,
        level: profile["level"] || @character.level,
        item_level: profile["equipped_item_level"],
        average_item_level: profile["average_item_level"],
        active_spec: localized(profile.dig("active_spec", "name")),
        playable_class: localized(profile.dig("character_class", "name")) || @character.playable_class,
        playable_race: localized(profile.dig("race", "name")) || @character.playable_race,
        faction: profile.dig("faction", "type")&.to_s&.downcase || @character.faction,
        guild_name: localized(profile.dig("guild", "name")),
        last_login_at: epoch_ms(profile["last_login_timestamp"])
      }
    end

    # A 404 here means "no keys this season", which is ordinary. Anything else
    # is a real failure and belongs to the caller's retry logic.
    def mythic_rating
      payload = client.mythic_keystone_profile(@character.realm_slug, @character.name)
      payload&.dig("current_mythic_rating", "rating")
    rescue Client::NotFound
      nil
    end

    def epoch_ms(value) = value.present? ? Time.zone.at(value.to_i / 1000) : nil

    def localized(value)
      return value if value.is_a?(String)
      return value["en_US"] || value.values.first if value.is_a?(Hash)

      nil
    end
  end
end
