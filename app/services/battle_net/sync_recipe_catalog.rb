module BattleNet
  # Build the recipe catalog from Blizzard's static profession data.
  #
  #   /data/wow/profession/index                    → 25 professions
  #   /data/wow/profession/{id}                     → its skill tiers
  #   /data/wow/profession/{id}/skill-tier/{tierId} → categories → recipes
  #
  # A closed expansion's recipe list never changes, so a tier we already hold is
  # skipped — the same immutability rule the Raider.io seasons and Warcraft Logs
  # zones use. Only the newest tier per profession is re-read, since a patch can
  # add to the live one. That takes steady state from ~350 requests to ~50.
  #
  # Static game data on the app token: no user involved, no per-character cost.
  class SyncRecipeCatalog
    Result = Struct.new(:professions, :tiers, :recipes, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(client: nil, now: Time.current, refresh_all: false)
      @client = client || Client.app
      @now = now
      @refresh_all = refresh_all
    end

    def call
      professions = Array(@client.profession_index["professions"])
      tiers = 0
      recipes = 0

      professions.each do |summary|
        id = summary["id"] or next

        detail = @client.profession(id)
        skill_tiers = Array(detail["skill_tiers"])
        newest = skill_tiers.max_by { |t| t["id"].to_i }

        skill_tiers.each do |tier|
          next unless sync?(tier, newest)

          recipes += sync_tier(detail, tier)
          tiers += 1
        end
      rescue Client::Error => e
        # One profession failing shouldn't cost the other 24.
        Rails.logger.warn("[wow] recipe catalog failed for profession #{id}: #{e.class}: #{e.message}")
      end

      Rails.logger.info("[wow] recipe catalog: #{recipes} recipes across #{tiers} tiers")
      Result.new(professions: professions.size, tiers: tiers, recipes: recipes)
    end

    private

    # A closed tier's recipes are fixed; the live one can still gain some.
    def sync?(tier, newest)
      return true if @refresh_all
      return true if tier["id"] == newest&.dig("id")

      !WowRecipe.in_tier(tier["id"]).exists?
    end

    def sync_tier(profession, tier)
      payload = @client.profession_skill_tier(profession["id"], tier["id"])

      Array(payload["categories"]).sum do |category|
        Array(category["recipes"]).count do |raw|
          store(profession, tier, category["name"], raw)
        end
      end
    rescue Client::NotFound
      0
    end

    def store(profession, tier, category, raw)
      id = raw["id"] or return false
      name = raw["name"].presence or return false

      recipe = WowRecipe.find_or_initialize_by(recipe_id: id)
      recipe.assign_attributes(
        name: name,
        profession_id: profession["id"], profession_name: profession["name"],
        skill_tier_id: tier["id"], skill_tier_name: tier["name"],
        category: category, synced_at: @now
      )
      recipe.save!
    end
  end
end
