module WowCharacters
  # Let a user assert that a character is theirs, without any Battle.net link.
  #
  # The point is reach: linking Battle.net is a whole OAuth ceremony, and plenty
  # of applicants won't do it. A claim gets their gear, score and parses in
  # front of a reviewer anyway. What it does NOT do is prove anything — that's
  # the difference between `claimed_at` and `verified_at`, and every surface
  # showing a claimed character to a third party has to say so.
  #
  # The character itself is looked up on Blizzard's public API first, so a claim
  # can only ever name a character that actually exists, and lands on the same
  # row a later OAuth verification would.
  class Claim
    Result = Struct.new(:character, :status, :error, keyword_init: true) do
      def ok? = character.present? && error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(user:, name:, realm_slug:, region: BattleNet::Client::DEFAULT_REGION, client: nil, now: Time.current)
      @user = user
      @name = name.to_s.strip
      @realm_slug = realm_slug.to_s.strip.downcase.tr(" ", "-")
      @region = BattleNet::Client.region?(region) ? region.to_s : BattleNet::Client::DEFAULT_REGION
      @client = client
      @now = now
    end

    def call
      return failure("Enter a character name and realm.") if @name.blank? || @realm_slug.blank?

      profile = client.character_profile(@realm_slug, @name)
      blizzard_id = profile&.dig("id") or return failure("Blizzard didn't recognise that character.")

      existing = WowCharacter.find_by(blizzard_id: blizzard_id)
      return conflict(existing) if existing && existing.user_id != @user.id

      character = existing || @user.wow_characters.new(blizzard_id: blizzard_id)
      character.assign_attributes(attributes_from(profile))
      # Claiming a character already verified through OAuth must not downgrade
      # it — the claim adds nothing Blizzard hasn't already confirmed.
      character.claimed_at ||= @now
      character.save!

      # With one character there is no other sensible main; with several this
      # is a no-op, since it only ever fills a gap.
      SetMain.ensure(@user)

      Result.new(character: character, status: existing ? :already_yours : :claimed)
    rescue BattleNet::Client::NotFound
      failure("No character called #{@name} on #{@realm_slug.titleize} (#{@region.upcase}).")
    rescue BattleNet::Client::Error => e
      Rails.logger.warn("[wow] claim failed for #{@name}-#{@realm_slug}: #{e.class}: #{e.message}")
      failure("Couldn't reach Blizzard just now. Please try again.")
    end

    private

    def client = @client ||= BattleNet::Client.app(region: @region)

    # Someone else already owns this character. Refuse rather than reassign:
    # a claim is an unproven assertion, and letting one silently take a
    # character off another user would make the weakest signal in the system
    # also the most destructive.
    def conflict(existing)
      if existing.verified?
        failure("That character is already linked to another account via Battle.net.")
      else
        failure("Someone else has already claimed that character. " \
                "Link your Battle.net account to prove it's yours.")
      end
    end

    def attributes_from(profile)
      realm = profile["realm"] || {}
      {
        name: profile["name"].presence || @name,
        realm: localized(realm["name"]).presence || @realm_slug.titleize,
        realm_slug: realm["slug"].presence || @realm_slug,
        realm_id: realm["id"],
        region: @region,
        level: profile["level"],
        playable_class: localized(profile.dig("character_class", "name")),
        playable_race: localized(profile.dig("race", "name")),
        faction: profile.dig("faction", "type")&.to_s&.downcase,
        # A claim says nothing about ownership, so this deliberately never
        # touches verified_at.
        missing_at: nil
      }.compact
    end

    def localized(value)
      return value if value.is_a?(String)
      return value["en_US"] || value.values.first if value.is_a?(Hash)

      nil
    end

    def failure(message) = Result.new(character: nil, status: :failed, error: message)
  end
end
