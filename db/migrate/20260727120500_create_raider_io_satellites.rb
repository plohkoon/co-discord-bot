class CreateRaiderIoSatellites < ActiveRecord::Migration[8.1]
  # Raider.io data moves off the character row into satellites, because most of
  # it is *immutable history*: once a season or a raid tier ends, its numbers
  # never change again. Stored per-row we fetch each one exactly once and keep
  # it forever; stored as a JSON blob on the character we'd re-fetch and
  # overwrite the whole history on every refresh.
  def change
    # --- Shared reference data (a few dozen rows, synced rarely) ---

    create_table :wow_seasons do |t|
      t.string :slug, null: false
      t.string :name
      t.string :short_name
      t.integer :expansion_id
      # Raider.io publishes per-region start/end times a few hours apart; US is
      # stored as canonical since it's only used to decide "has this ended".
      t.datetime :starts_at
      t.datetime :ends_at
      # Raider.io mints extra slugs for events and re-cuts alongside the real
      # ladder (-break-the-meta, -cutoffs, -post, -meta-vs-meta, -legion-remix).
      # Nobody recruits on those, so only `ranked` seasons are backfilled.
      t.boolean :ranked, null: false, default: false
      t.datetime :synced_at

      t.timestamps
    end
    add_index :wow_seasons, :slug, unique: true
    add_index :wow_seasons, %i[ranked ends_at]

    create_table :wow_raids do |t|
      t.string :slug, null: false
      t.string :name
      t.string :short_name
      t.integer :expansion_id
      t.integer :boss_count
      t.datetime :synced_at

      t.timestamps
    end
    add_index :wow_raids, :slug, unique: true

    # --- Per-character history ---

    create_table :wow_character_seasons do |t|
      t.references :wow_character, null: false, foreign_key: true
      # Joined to wow_seasons by slug rather than an FK: Raider.io can report a
      # season we haven't synced yet, and losing the score to a missing parent
      # row would be worse than an unlabelled slug.
      t.string :season_slug, null: false
      t.decimal :score_all, precision: 7, scale: 1
      t.decimal :score_tank, precision: 7, scale: 1
      t.decimal :score_healer, precision: 7, scale: 1
      t.decimal :score_dps, precision: 7, scale: 1
      t.datetime :fetched_at, null: false

      t.timestamps
    end
    add_index :wow_character_seasons, %i[wow_character_id season_slug], unique: true
    add_index :wow_character_seasons, :season_slug

    create_table :wow_character_raids do |t|
      t.references :wow_character, null: false, foreign_key: true
      t.string :raid_slug, null: false
      t.string :summary
      t.integer :total_bosses
      t.integer :normal_bosses_killed, default: 0
      t.integer :heroic_bosses_killed, default: 0
      t.integer :mythic_bosses_killed, default: 0
      t.datetime :fetched_at, null: false

      t.timestamps
    end
    add_index :wow_character_raids, %i[wow_character_id raid_slug], unique: true

    # The JSON blobs these tables replace. raider_io_score/role stay on the
    # character as a denormalised copy of the *current* season, so listing a
    # team by score stays a single-table query.
    remove_column :wow_characters, :raider_io_scores, :text
    remove_column :wow_characters, :raid_progression, :text
  end
end
