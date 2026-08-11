class CreateWowCharacters < ActiveRecord::Migration[8.1]
  def change
    create_table :wow_characters do |t|
      t.references :battle_net_account, null: false, foreign_key: true
      # Blizzard's character id — survives renames and realm transfers, which
      # name+realm does not. This is the real key.
      t.bigint :blizzard_id, null: false
      t.string :name, null: false
      t.string :realm, null: false
      t.string :realm_slug, null: false
      t.bigint :realm_id
      t.integer :level
      t.string :playable_class
      t.string :playable_race
      t.string :faction
      # Set when the character came back from the owner's own OAuth token —
      # i.e. Blizzard confirmed they own it. Nothing else may set this.
      t.datetime :verified_at

      t.timestamps
    end

    add_index :wow_characters, %i[battle_net_account_id blizzard_id], unique: true
  end
end
