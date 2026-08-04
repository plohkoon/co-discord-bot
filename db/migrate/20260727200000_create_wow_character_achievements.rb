class CreateWowCharacterAchievements < ActiveRecord::Migration[8.1]
  # The career record — the one thing no other source can supply.
  #
  # Raider.io says what someone has killed *now*; only the achievement proves
  # they killed it **while it was current**, which is the entire meaning of
  # Ahead of the Curve and Cutting Edge. Likewise Blizzard serves no historical
  # PvP ratings, so a Gladiator achievement is the only evidence a past season
  # ever happened for that character.
  #
  # Only career-defining achievements are stored. The endpoint returns ~3,600
  # rows per character (measured); keeping them all would be absurd, and the
  # ~1% that matter are what anyone would ever ask about.
  def change
    create_table :wow_character_achievements do |t|
      t.references :wow_character, null: false, foreign_key: true
      t.bigint :blizzard_id, null: false
      t.string :name, null: false
      # aotc | cutting_edge | gladiator | pvp_title | keystone — assigned by
      # WowCharacterAchievement::CATEGORIES so the rows are queryable without
      # re-matching names at read time.
      t.string :category, null: false
      # When they earned it. The whole point: "Cutting Edge in 2024" is a
      # different claim from "Cutting Edge eventually".
      t.datetime :completed_at

      t.timestamps
    end

    add_index :wow_character_achievements, %i[wow_character_id blizzard_id], unique: true
    add_index :wow_character_achievements, %i[wow_character_id category]

    # Achievements are a heavy request (~3,600 entries) and near-static once
    # earned, so they get their own slow cadence rather than riding the hourly
    # character sweep.
    add_column :wow_characters, :achievements_refreshed_at, :datetime
    add_index :wow_characters, :achievements_refreshed_at
  end
end
