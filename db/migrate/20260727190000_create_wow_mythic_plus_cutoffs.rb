class CreateWowMythicPlusCutoffs < ActiveRecord::Migration[8.1]
  # Mythic+ score percentiles — "top 0.1%", "top 1%", and the named title tiers.
  #
  # The counterpart to wow_pvp_cutoffs, and needed for the same reason: a stored
  # score of 3400 is uninterpretable later unless we also stored what 3400 was
  # worth at the time. Blizzard publishes nothing here (there is no M+ analogue
  # to pvp-reward), so Raider.io's computed quantiles are the only source.
  #
  # Two things PvP cutoffs don't have, both of which earn their columns:
  #   - a POPULATION DENOMINATOR, so "top 0.1%" is a real percentile with a
  #     headcount rather than a bare threshold;
  #   - a FACTION split, which is not cosmetic — measured live in season-mn-1,
  #     US Horde needed 4022.79 for top 0.1% while Alliance needed 4205.96.
  def change
    create_table :wow_mythic_plus_cutoffs do |t|
      t.string :season_slug, null: false
      t.string :region, null: false
      # horde | alliance | all — "all" is the combined ladder, not a sum.
      t.string :faction, null: false
      # p999, p990, p900, p750, p600 (percentiles) or keystoneHero,
      # keystoneMaster, … (named title tiers). Raider.io's own key, kept verbatim
      # rather than renamed — it's the only stable handle they publish.
      t.string :quantile_key, null: false
      # 0.999 for p999. Stored because the key alone doesn't say what it means.
      t.decimal :quantile, precision: 6, scale: 5
      t.decimal :min_score, precision: 8, scale: 2, null: false
      t.integer :population_count
      t.integer :total_population
      t.datetime :captured_at, null: false

      t.timestamps
    end

    # A changed bar is a NEW row — the cutoff drifts all season as the ladder
    # fills, and that movement is the interesting part.
    add_index :wow_mythic_plus_cutoffs,
              %i[season_slug region faction quantile_key min_score],
              unique: true, name: "index_mplus_cutoffs_on_season_region_faction_key_score"
    add_index :wow_mythic_plus_cutoffs, %i[season_slug region quantile_key]
  end
end
