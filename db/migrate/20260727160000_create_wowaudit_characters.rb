class CreateWowauditCharacters < ActiveRecord::Migration[8.1]
  # The roster as the team's officers maintain it in wowaudit.
  #
  # This is the first source that knows who is *supposed* to be on a team from
  # the raid-leading side, independent of Discord roles and independent of who
  # has bothered to link Battle.net. Holding it alongside our own records is
  # what makes the three views comparable later.
  def change
    create_table :wowaudit_characters do |t|
      t.references :guild, null: false, foreign_key: true, type: :bigint
      t.references :team, null: false, foreign_key: true
      # wowaudit's own character id — stable, and the key its other endpoints
      # (wishlists, raid signups) address characters by.
      t.integer :wowaudit_id, null: false
      t.string :name, null: false
      t.string :realm
      t.string :character_class
      t.string :role

      # Matched to our own record by name+realm when we have one. Nullable and
      # expected to stay that way for anyone who hasn't linked Battle.net —
      # "unmatched" is an ordinary state, not a failure.
      t.references :wow_character, null: true, foreign_key: true

      t.datetime :synced_at, null: false

      t.timestamps
    end

    add_index :wowaudit_characters, %i[team_id wowaudit_id], unique: true
    add_index :wowaudit_characters, %i[guild_id name]
  end
end
