module BattleNet
  # Capture a character's career-defining achievements.
  #
  # One request, but a **heavy** one — measured at ~3,600 entries for a
  # long-lived character — of which roughly 1% are worth keeping. That weight is
  # why this has its own slow cadence (WowCharacterAchievementsSweepJob) instead
  # of riding the hourly character refresh.
  #
  # Worth the weight because nothing else can supply it: Raider.io reports what
  # someone has killed *now*, and Blizzard serves no historical PvP ratings at
  # all. Only the achievement proves they did it **while it was current** — the
  # entire meaning of Ahead of the Curve, Cutting Edge, and a season Gladiator
  # title.
  class RefreshCharacterAchievements
    Result = Struct.new(:character, :status, :stored, :scanned, keyword_init: true) do
      def ok? = status == :refreshed
    end

    def self.call(...) = new(...).call

    def initialize(character, client: nil, now: Time.current)
      @character = character
      @client = client || Client.app(region: character.region)
      @now = now
    end

    def call
      payload = @client.character_achievements(@character.realm_slug, @character.name)
      entries = Array(payload&.dig("achievements"))

      stored = 0
      ActiveRecord::Base.transaction do
        entries.each { |raw| stored += 1 if store(raw) }
        @character.update!(achievements_refreshed_at: @now)
      end

      Result.new(character: @character, status: :refreshed, stored: stored, scanned: entries.size)
    rescue Client::NotFound
      @character.update!(achievements_refreshed_at: @now)
      Result.new(character: @character, status: :missing, stored: 0, scanned: 0)
    end

    private

    def store(raw)
      # Unearned achievements come back in the same list with no completion
      # timestamp — an achievement someone is *working towards* is not a
      # credential, so those are skipped entirely.
      completed = raw["completed_timestamp"] or return false

      id = raw.dig("achievement", "id") or return false
      name = raw.dig("achievement", "name").presence or return false

      category = WowCharacterAchievement.categorize(id, name) or return false

      row = @character.wow_character_achievements.find_or_initialize_by(blizzard_id: id)
      row.assign_attributes(name: name, category: category, completed_at: epoch_ms(completed))
      row.save!
    end

    def epoch_ms(value) = value.present? ? Time.zone.at(value.to_i / 1000) : nil
  end
end
