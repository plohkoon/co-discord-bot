class CreateWarcraftLogsTables < ActiveRecord::Migration[8.1]
  # Warcraft Logs parse percentiles — how a character actually performed in a
  # raid, which is the metric raid leads recruit on and neither Blizzard nor
  # Raider.io provides.
  #
  # Same caching shape as the Raider.io satellites, and for the same reason:
  # Warcraft Logs marks a closed tier's zone `frozen`, and such a zone's
  # rankings can never change again. Those rows are fetched once and then only
  # read; only the live tier is re-fetched.
  def change
    # Reference data: Warcraft Logs' own raid zones. Kept separate from
    # `wow_raids` (Raider.io's view of the same tiers) rather than reconciled —
    # the two services slug and split tiers differently, and guessing at a
    # mapping would corrupt both.
    create_table :warcraft_logs_zones do |t|
      t.integer :wcl_id, null: false
      t.string :name
      t.integer :expansion_id
      t.string :expansion_name
      # Warcraft Logs calls this `frozen` — the tier is closed and its
      # rankings can never change again. Stored as `closed` because Active
      # Record refuses a `frozen` attribute (it would shadow Object#frozen?),
      # and "closed tier" is the clearer domain word regardless.
      t.boolean :closed, null: false, default: false
      t.datetime :synced_at

      t.timestamps
    end
    add_index :warcraft_logs_zones, :wcl_id, unique: true
    add_index :warcraft_logs_zones, %i[closed expansion_id]

    create_table :warcraft_logs_rankings do |t|
      t.references :wow_character, null: false, foreign_key: true
      t.integer :wcl_zone_id, null: false
      # Blizzard difficulty ids: 3 normal, 4 heroic, 5 mythic. Stored because a
      # character has a different (and differently interesting) parse at each.
      t.integer :difficulty, null: false

      # The two headline numbers. "Best" is their peak, "median" is what they
      # do on an ordinary night — recruiters care about the second one more.
      t.decimal :best_performance_average, precision: 6, scale: 2
      t.decimal :median_performance_average, precision: 6, scale: 2
      # All-stars points and rank within their spec for the tier.
      t.decimal :all_stars_points, precision: 10, scale: 2
      t.integer :all_stars_rank
      t.integer :all_stars_rank_percent
      # How many logged boss kills back the numbers above — a 99 parse off one
      # kill is not the same claim as a 99 off thirty.
      t.integer :total_kills
      t.string :spec_name
      t.string :metric

      t.datetime :fetched_at, null: false

      t.timestamps
    end
    add_index :warcraft_logs_rankings, %i[wow_character_id wcl_zone_id difficulty],
              unique: true, name: "index_wcl_rankings_on_character_zone_difficulty"

    change_table :wow_characters, bulk: true do |t|
      # Warcraft Logs' own character id — stable across renames, unlike the
      # name+server lookup we have to use to find them the first time.
      t.integer :warcraft_logs_id
      t.datetime :warcraft_logs_refreshed_at
      # Set when Warcraft Logs has never seen this character (never been in a
      # logged raid). Ordinary, not an error — but it stops the sweep re-asking.
      t.datetime :warcraft_logs_missing_at
    end
  end
end
