class CreateWowCharacterProfessions < ActiveRecord::Migration[8.1]
  # Which professions a character has, and how far along each expansion's tier
  # they are.
  #
  # Record-keeping for now. The obvious later use is attaching it to the
  # profession roles that already exist in Discord, but that's a *using*
  # question and lives in TODOS.
  def change
    create_table :wow_character_professions do |t|
      t.references :wow_character, null: false, foreign_key: true
      t.integer :profession_id, null: false
      t.string :name, null: false
      # primary | secondary. Blizzard splits them, and the distinction matters:
      # primaries are the two that are capped and chosen, secondaries
      # (Cooking, Fishing, Archaeology) are free and near-universal.
      t.string :kind, null: false

      t.timestamps
    end
    add_index :wow_character_professions, %i[wow_character_id profession_id], unique: true
    add_index :wow_character_professions, :name

    # One row per expansion tier — "Midnight Tailoring 30/100". Skill is tracked
    # per expansion, so a character can be capped in Classic and untouched in
    # the current tier; only the latter tells you whether they can actually
    # craft anything useful today.
    create_table :wow_character_profession_tiers do |t|
      t.references :wow_character_profession, null: false, foreign_key: true,
                   index: { name: "index_profession_tiers_on_profession_id" }
      t.integer :tier_id, null: false
      t.string :name, null: false
      t.integer :skill_points
      t.integer :max_skill_points
      # Recipes are in the same response but not stored: one live character had
      # 908 of them, which is a far larger dataset than the professions
      # themselves and answers a question ("who can craft X") nobody has asked
      # yet. The count is kept so the decision can be revisited with numbers.
      t.integer :known_recipe_count, default: 0

      t.timestamps
    end
    add_index :wow_character_profession_tiers, %i[wow_character_profession_id tier_id],
              unique: true, name: "index_profession_tiers_on_profession_and_tier"

    add_column :wow_characters, :professions_refreshed_at, :datetime
  end
end
