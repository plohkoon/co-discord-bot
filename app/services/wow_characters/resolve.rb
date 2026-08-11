module WowCharacters
  # Turn what someone typed — "Thrall-Sargeras", "thrall - sargeras",
  # "Jörmûngandr-Area 52" — into a claimed character.
  #
  # Used by the apply flow, where the input is free text from a Discord modal
  # and a typo is entirely likely. The contract is deliberately forgiving:
  #
  #   - it NEVER raises and never blocks whatever called it. An application must
  #     not be lost because someone misspelt their own character.
  #   - `unresolved` is an ordinary outcome, not an error, and carries the raw
  #     input so a human can be shown what they typed.
  #
  # Resolution goes through WowCharacters::Claim, so the same ownership and
  # conflict rules apply: an unproven claim can never take a character from
  # someone who verified it.
  class Resolve
    Result = Struct.new(:character, :status, :input, :error, keyword_init: true) do
      def ok? = character.present?
      # Typed something we couldn't turn into a character — worth telling them.
      def unresolved? = character.nil? && input.present?
    end

    # "Thrall-Sargeras" is how players write it. Realms with spaces ("Area 52")
    # are hyphenated by Blizzard, so both forms have to parse.
    SEPARATOR = /\s*[-–—]\s*/

    def self.call(...) = new(...).call

    def initialize(user:, input:, region: BattleNet::Client::DEFAULT_REGION, client: nil, now: Time.current)
      @user = user
      @input = input.to_s.strip
      @region = region
      @client = client
      @now = now
    end

    def call
      return Result.new(character: nil, status: :blank, input: nil) if @input.blank?

      name, realm = split
      return unresolved("Give it as Name-Realm, like Thrall-Sargeras.") if name.blank? || realm.blank?

      claim = Claim.call(user: @user, name: name, realm_slug: realm, region: @region,
                         client: @client, now: @now)
      return unresolved(claim.error) unless claim.ok?

      Result.new(character: claim.character, status: claim.status, input: @input)
    rescue => e
      # This service promises never to raise (see the class comment): the
      # review message is repainted from whatever it returns, so an exception
      # here would strand it on "Loading…" forever. Any unforeseen input that
      # slips past validation degrades to "couldn't resolve", not a crash.
      Rails.logger.warn("[wow] resolve failed for #{@input.inspect}: #{e.class}: #{e.message}")
      unresolved("Couldn't look that character up. Double-check the Name-Realm.")
    end

    private

    # Split on the LAST separator: character names contain hyphens far less
    # often than realm names do ("Area 52" → "area-52"), so everything after the
    # final one would be wrong. Splitting on the first keeps multi-word realms
    # intact.
    def split
      name, realm = @input.split(SEPARATOR, 2)
      [ name.to_s.strip, realm.to_s.strip.downcase.tr(" ", "-") ]
    end

    def unresolved(error)
      Result.new(character: nil, status: :unresolved, input: @input, error: error)
    end
  end
end
