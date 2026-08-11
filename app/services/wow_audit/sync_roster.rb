module WowAudit
  # Pull a team's wowaudit roster and match it against characters we already
  # know about.
  #
  # The match is by **name + realm**, because that's the only key the two sides
  # share — wowaudit issues its own character ids and doesn't publish Blizzard's.
  # Both are normalised (case, unicode form, realm spacing) before comparing,
  # since the two services disagree on all three.
  #
  # An unmatched roster entry is the ordinary case, not a failure: most teams
  # have members who've never linked Battle.net here. Nothing is deleted or
  # flagged on their behalf — this service only records what wowaudit says.
  class SyncRoster
    Result = Struct.new(:team, :synced, :matched, :removed, :error, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(team, client: nil, now: Time.current)
      @team = team
      @client = client || Client.new(api_key: team.wowaudit_api_key)
      @now = now
    end

    def call
      return failure("No wowaudit API key set.") unless @client.configured?

      roster = @client.characters
      attributes = roster.filter_map { |raw| character_attributes(raw) }

      synced = 0
      matched = 0
      ActiveRecord::Base.transaction do
        lookup = wow_character_lookup
        attributes.each do |attrs|
          row = @team.wowaudit_characters.find_or_initialize_by(wowaudit_id: attrs[:wowaudit_id])
          row.assign_attributes(attrs.merge(
            wow_character_id: lookup[WowauditCharacter.match_key(attrs[:name], attrs[:realm])],
            synced_at: @now
          ))
          row.save!
          synced += 1
          matched += 1 if row.wow_character_id
        end
        removed = prune(attributes)
        @team.update!(wowaudit_verified_at: @now)
        return Result.new(team: @team, synced: synced, matched: matched, removed: removed)
      end
    rescue Client::Unauthorized
      @team.update!(wowaudit_verified_at: nil)
      failure("wowaudit rejected the key.")
    rescue Client::Error => e
      failure("wowaudit request failed: #{e.message}")
    end

    private

    # Characters this app already knows about, keyed the same way. Verified
    # links only — an unverified guess is worse than no match.
    def wow_character_lookup
      WowCharacter.verified.includes(:battle_net_account).each_with_object({}) do |character, memo|
        memo[WowauditCharacter.match_key(character.name, character.realm)] ||= character.id
      end
    end

    def character_attributes(raw)
      return nil unless raw.is_a?(Hash)

      id = raw["id"] or return nil
      name = raw["name"].presence or return nil

      {
        wowaudit_id: id,
        name: name,
        realm: raw["realm"].presence,
        # `class` is a reserved word everywhere; wowaudit sends it anyway.
        character_class: raw["class"].presence,
        role: raw["role"].presence&.downcase
      }
    end

    # Someone taken off the wowaudit roster is off the team's list — that's the
    # officers' decision, recorded. It does NOT touch Discord roles or
    # memberships; this service records, it doesn't act.
    def prune(attributes)
      keep = attributes.map { |a| a[:wowaudit_id] }
      scope = @team.wowaudit_characters
      scope = scope.where.not(wowaudit_id: keep) if keep.any?
      scope.delete_all
    end

    def failure(message) = Result.new(team: @team, synced: 0, matched: 0, removed: 0, error: message)
  end
end
