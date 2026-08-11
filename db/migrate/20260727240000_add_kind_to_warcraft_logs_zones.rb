class AddKindToWarcraftLogsZones < ActiveRecord::Migration[8.1]
  # Warcraft Logs puts raid tiers and Mythic+ seasons in the same `zones` list,
  # and both carry rankings. Without telling them apart:
  #
  #   - M+ rankings get stored as if they were raid parses, and
  #   - because M+ uses difficulty 10 and mythic raid uses 5, the M+ row wins
  #     any "highest difficulty" comparison and hijacks the headline parse.
  #
  # Verified live: a character's raid parse was 99 while the M+ zone reported
  # 100, and the M+ number was the one surfacing.
  #
  # The zone's own difficulty list is the signal — raid zones offer 3/4/5
  # (Normal/Heroic/Mythic), M+ zones offer 10.
  def change
    add_column :warcraft_logs_zones, :kind, :string, null: false, default: "raid"
    add_index :warcraft_logs_zones, :kind
  end
end
