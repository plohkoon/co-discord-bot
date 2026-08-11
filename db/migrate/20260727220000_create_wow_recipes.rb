class CreateWowRecipes < ActiveRecord::Migration[8.1]
  # The recipe catalog, and who knows what.
  #
  # Split into a shared catalog plus a thin join rather than one fat table per
  # character: a character knows ~500-900 recipes, so duplicating the name and
  # profession on every row would make this by far the heaviest table in the
  # schema for no reason. The join carries two integers.
  #
  # The catalog comes from Blizzard's **static** profession data, not from what
  # characters happen to know. That's the difference between "nobody has this
  # recipe" and "we've never heard of that recipe" — only the first is a useful
  # answer to someone asking whether it's worth finding a crafter.
  def change
    create_table :wow_recipes do |t|
      t.bigint :recipe_id, null: false
      t.string :name, null: false
      t.integer :profession_id
      t.string :profession_name
      # Recipes belong to a skill TIER, not a profession — the same profession
      # has a different list every expansion.
      t.integer :skill_tier_id
      t.string :skill_tier_name
      # "Void Potions", "Transmutations", "Cauldrons" — Blizzard's own grouping,
      # available only from the static skill-tier endpoint. The character
      # payload has no categories, which is half the reason the catalog is
      # synced separately.
      t.string :category
      t.datetime :synced_at

      t.timestamps
    end
    add_index :wow_recipes, :recipe_id, unique: true
    add_index :wow_recipes, :name
    add_index :wow_recipes, :skill_tier_id
    add_index :wow_recipes, :profession_id

    create_table :wow_character_recipes do |t|
      t.references :wow_character, null: false, foreign_key: true
      # Joined on Blizzard's recipe id rather than a foreign key to wow_recipes,
      # for the same reason the other satellites join by natural key: a
      # character can know a recipe the catalog sync hasn't reached yet, and an
      # unlabelled row beats a dropped one.
      t.bigint :recipe_id, null: false

      t.timestamps
    end
    # Both directions are real questions: "who knows this recipe" and "what can
    # this character make".
    add_index :wow_character_recipes, %i[wow_character_id recipe_id], unique: true
    add_index :wow_character_recipes, :recipe_id
  end
end
