class AddLiveDataToWowCharacters < ActiveRecord::Migration[8.1]
  # Data that changes as someone plays, refreshed from Blizzard's PUBLIC
  # endpoints with the app's client-credentials token — no user token, so this
  # keeps working forever after the one-time link.
  def change
    change_table :wow_characters, bulk: true do |t|
      t.integer :item_level            # equipped
      t.integer :average_item_level    # includes bags — the "ilvl" people quote
      t.string :active_spec
      t.string :guild_name
      t.decimal :mythic_rating, precision: 7, scale: 2 # current-season M+ score
      t.datetime :last_login_at
      t.datetime :refreshed_at
      # Blizzard 404s the character: deleted, or renamed/transferred (the public
      # endpoint is addressed by name, so we can't follow it). Cleared as soon
      # as a refresh succeeds again; re-linking repairs a rename.
      t.datetime :missing_at
    end

    # The sweep's query: oldest-refreshed first, nulls (never refreshed) first.
    add_index :wow_characters, :refreshed_at
  end
end
