class CreateWowEncounters < ActiveRecord::Migration[8.1]
  # The join between Raider.io's raid tiers and Warcraft Logs' raid zones.
  #
  # The two services carve tiers up differently — Raider.io's "MN Tier 1 (VS /
  # DR / MQD)" is one nine-boss tier spanning three raid instances, which
  # Warcraft Logs may well split — so matching them by name or slug would be
  # guesswork. Individual **bosses** are unambiguous though: Raider.io publishes
  # Blizzard's journal encounter id as its encounter `id`, and Warcraft Logs
  # publishes the same number as `Encounter.journalID`. Same namespace, exact
  # match.
  #
  # So this table is keyed on the journal id, each service fills in its own
  # column during its own sync, and the tier mapping is *derived* from which
  # bosses they share rather than asserted.
  def change
    create_table :wow_encounters do |t|
      t.bigint :journal_id, null: false
      t.string :name
      # Raider.io's raid slug (wow_raids.slug). Filled by RaiderIo::SyncStaticData.
      t.string :raid_slug
      # Warcraft Logs' zone id (warcraft_logs_zones.wcl_id). Filled by
      # WarcraftLogs::SyncZones — stays null until credentials are configured.
      t.integer :wcl_zone_id
      t.datetime :synced_at

      t.timestamps
    end

    add_index :wow_encounters, :journal_id, unique: true
    add_index :wow_encounters, :raid_slug
    add_index :wow_encounters, :wcl_zone_id
  end
end
