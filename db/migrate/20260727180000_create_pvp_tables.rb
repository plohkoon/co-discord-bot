class CreatePvpTables < ActiveRecord::Migration[8.1]
  # PvP inverts the PvE data situation: Blizzard is the only real source
  # (Raider.io has literally zero PvP coverage), and — crucially — Blizzard
  # serves a character's rating for the CURRENT SEASON ONLY. There is no
  # historical per-character endpoint, so unlike the Raider.io season backfill,
  # anything not recorded while it is live is gone permanently. These tables are
  # the only place that history can exist.
  def change
    # --- Reference data ---

    create_table :wow_pvp_seasons do |t|
      t.integer :blizzard_id, null: false
      t.string :name # "Player vs. Player (Midnight Season 1)"
      t.datetime :starts_at
      # Blizzard names one season current; everything else is history and can
      # never change again.
      t.boolean :current, null: false, default: false
      t.datetime :synced_at

      t.timestamps
    end
    add_index :wow_pvp_seasons, :blizzard_id, unique: true

    # Unranked / Combatant I..II / Challenger I..II / Rival I..II / Duelist /
    # Elite, with the rating each starts at. Per bracket, and they move between
    # seasons — this is what turns `tier: {id: 14}` into "Elite, 2275+".
    create_table :wow_pvp_tiers do |t|
      t.integer :blizzard_id, null: false
      t.string :name
      t.integer :min_rating
      t.integer :max_rating
      t.string :bracket_type
      t.datetime :synced_at

      t.timestamps
    end
    add_index :wow_pvp_tiers, :blizzard_id, unique: true

    # Title cutoffs, per season, bracket AND specialisation.
    #
    # This table is why PvP ratings are worth storing at all. Measured live in
    # season 41: the same Shuffle title needed 2205 on one spec and 2998 on
    # another. A rating without its contemporaneous cutoff is uninterpretable,
    # and cutoffs move throughout a season — so a changed value is a new row,
    # giving a step history rather than an overwrite.
    create_table :wow_pvp_cutoffs do |t|
      t.integer :season_id, null: false
      t.string :bracket_type, null: false # SHUFFLE | BLITZ | ARENA_3v3 | ...
      t.integer :specialization_id
      t.string :specialization_name
      t.integer :rating_cutoff, null: false
      t.string :achievement_name
      t.datetime :captured_at, null: false

      t.timestamps
    end
    add_index :wow_pvp_cutoffs, %i[season_id bracket_type specialization_id rating_cutoff],
              unique: true, name: "index_pvp_cutoffs_on_season_bracket_spec_rating"

    # --- Per character ---

    # One row per character per season per bracket.
    #
    # "Bracket" is doing more work here than in PvE: 2v2/3v3/rbg are one rating
    # each, but Solo Shuffle and Blitz are rated PER SPECIALISATION, so one
    # character legitimately holds several at once (measured: shuffle-mage-frost,
    # shuffle-mage-fire and blitz-mage-frost simultaneously). The raw slug is
    # kept alongside a parsed type/spec so neither shape has to be inferred.
    create_table :wow_character_pvp_ratings do |t|
      t.references :wow_character, null: false, foreign_key: true
      t.integer :season_id, null: false
      t.string :bracket, null: false      # "3v3", "shuffle-mage-frost"
      t.string :bracket_type, null: false # "3v3", "shuffle"
      t.string :spec_slug                 # "mage-frost" for shuffle/blitz

      t.integer :rating
      t.integer :tier_id
      t.integer :played, default: 0
      t.integer :won, default: 0
      t.integer :lost, default: 0
      t.integer :weekly_played, default: 0
      t.integer :weekly_won, default: 0
      t.integer :weekly_lost, default: 0

      t.datetime :fetched_at, null: false

      t.timestamps
    end
    add_index :wow_character_pvp_ratings, %i[wow_character_id season_id bracket],
              unique: true, name: "index_pvp_ratings_on_character_season_bracket"
    add_index :wow_character_pvp_ratings, %i[season_id bracket_type rating]

    change_table :wow_characters, bulk: true do |t|
      t.integer :honor_level
      t.bigint :honorable_kills
      t.datetime :pvp_refreshed_at
    end
  end
end
