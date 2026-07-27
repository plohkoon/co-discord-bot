module BattleNet
  # Record which professions a character has and how far along each expansion's
  # tier they are.
  #
  # One cheap request, but professions move at the speed of someone deciding to
  # level Enchanting — so it self-throttles on `professions_refreshed_at` rather
  # than re-asking every hour. That keeps it free to call from the ordinary
  # character refresh without thinking about it.
  #
  # Known recipe ids ride along in the same response and are reconciled into
  # wow_character_recipes — a thin two-integer join against the shared catalog
  # (see BattleNet::SyncRecipeCatalog), rather than duplicating names per
  # character. ~500-900 per character, so the full known set is replaced each
  # refresh rather than diffed field by field.
  class RefreshCharacterProfessions
    Result = Struct.new(:character, :status, :professions, keyword_init: true) do
      def ok? = status == :refreshed
    end

    STALE_AFTER = 7.days

    def self.call(...) = new(...).call

    def initialize(character, client: nil, now: Time.current, stale_after: STALE_AFTER)
      @character = character
      @client = client || Client.app(region: character.region)
      @now = now
      @stale_after = stale_after
    end

    def call
      return skipped if fresh?

      payload = @client.character_professions(@character.realm_slug, @character.name)
      groups = {
        WowCharacterProfession::PRIMARY => Array(payload&.dig("primaries")),
        WowCharacterProfession::SECONDARY => Array(payload&.dig("secondaries"))
      }

      seen = []
      recipe_ids = []
      ActiveRecord::Base.transaction do
        groups.each do |kind, entries|
          entries.each do |raw|
            seen << store(kind, raw)
            recipe_ids.concat(recipe_ids_in(raw))
          end
        end
        prune(seen.compact)
        sync_recipes(recipe_ids.uniq)
        @character.update!(professions_refreshed_at: @now)
      end

      Result.new(character: @character, status: :refreshed, professions: seen.compact.size)
    rescue Client::NotFound
      @character.update!(professions_refreshed_at: @now)
      Result.new(character: @character, status: :missing, professions: 0)
    end

    private

    def fresh?
      @stale_after.present? && @character.professions_refreshed_at.present? &&
        @character.professions_refreshed_at > @now - @stale_after
    end

    def skipped = Result.new(character: @character, status: :skipped, professions: 0)

    def store(kind, raw)
      id = raw.dig("profession", "id") or return nil
      name = raw.dig("profession", "name").presence or return nil

      profession = @character.wow_character_professions.find_or_initialize_by(profession_id: id)
      profession.assign_attributes(name: name, kind: kind)
      profession.save!
      store_tiers(profession, Array(raw["tiers"]))
      id
    end

    def store_tiers(profession, tiers)
      kept = tiers.filter_map do |raw|
        tier_id = raw.dig("tier", "id") or next nil

        row = profession.wow_character_profession_tiers.find_or_initialize_by(tier_id: tier_id)
        row.assign_attributes(
          name: raw.dig("tier", "name").presence || "Tier #{tier_id}",
          skill_points: raw["skill_points"],
          max_skill_points: raw["max_skill_points"],
          known_recipe_count: Array(raw["known_recipes"]).size
        )
        row.save!
        tier_id
      end

      # A tier can't really disappear, but an unlearned profession's can — keep
      # the stored set matching what Blizzard reports rather than accumulating.
      profession.wow_character_profession_tiers.where.not(tier_id: kept).delete_all if kept.any?
    end

    def recipe_ids_in(raw)
      Array(raw["tiers"]).flat_map { |tier| Array(tier["known_recipes"]).filter_map { |r| r["id"] } }
    end

    # Replace the whole known set. Recipes are effectively never unlearned, but
    # dropping a profession takes its recipes with it, so reconciling the full
    # list is both simpler and more correct than adding-only.
    def sync_recipes(ids)
      existing = @character.wow_character_recipes.pluck(:recipe_id)
      (ids - existing).each { |id| @character.wow_character_recipes.create!(recipe_id: id) }
      @character.wow_character_recipes.where.not(recipe_id: ids).delete_all if ids.any?
      @character.wow_character_recipes.delete_all if ids.empty?
    end

    # Professions are droppable. Someone who abandons Enchanting for Alchemy
    # should stop showing as an enchanter.
    def prune(seen)
      scope = @character.wow_character_professions
      scope = scope.where.not(profession_id: seen) if seen.any?
      scope.destroy_all
    end
  end
end
