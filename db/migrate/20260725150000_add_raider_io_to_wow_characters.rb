class AddRaiderIoToWowCharacters < ActiveRecord::Migration[8.1]
  # Raider.io data that Blizzard's API doesn't give us in usable form:
  # raid progression per tier, and the M+ score split by role.
  def change
    change_table :wow_characters, bulk: true do |t|
      t.decimal :raider_io_score, precision: 7, scale: 1
      # tank | healer | dps — the character's current spec role. The single most
      # useful field for team composition, and Blizzard only exposes the spec.
      t.string :raider_io_role
      # {"all"=>2903.6, "dps"=>0, "healer"=>0, "tank"=>2903.6}
      t.text :raider_io_scores
      # {"tier-mn-1"=>"1/9 M", "sporefall"=>"1/1 H"} — slug => summary, empty
      # summaries dropped.
      t.text :raid_progression
      t.datetime :raider_io_refreshed_at
    end

    add_index :wow_characters, :raider_io_refreshed_at
  end
end
