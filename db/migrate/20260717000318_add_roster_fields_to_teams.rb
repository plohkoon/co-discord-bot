class AddRosterFieldsToTeams < ActiveRecord::Migration[8.1]
  def change
    # Roster headers ("PvE Teams ⚔️") — created on the fly from /team create|edit.
    create_table :team_categories do |t|
      t.bigint :guild_id, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.timestamps

      t.index :guild_id
      t.index %i[guild_id name], unique: true
    end
    add_foreign_key :team_categories, :guilds

    change_table :teams do |t|
      t.integer :team_category_id
      t.index :team_category_id
      # Free-form roster lines, rendered verbatim in the directory message.
      t.text :team_type
      t.text :progression
      t.text :requirements
      t.text :date_and_time
      t.text :current_needs
      # Where this team's directory block was last posted, so edits to the
      # team auto-refresh the message.
      t.bigint :roster_channel_id
      t.bigint :roster_message_id
    end
    add_foreign_key :teams, :team_categories
  end
end
