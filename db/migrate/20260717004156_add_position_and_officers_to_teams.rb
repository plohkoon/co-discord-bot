class AddPositionAndOfficersToTeams < ActiveRecord::Migration[8.1]
  def change
    # Sort order within the roster category (lower first, ties by name).
    add_column :teams, :position, :integer, default: 0, null: false

    # Local mirror of who holds each team's officer role, maintained by the
    # member_update listener (like memberships) — so nothing ever has to page
    # the guild's full member list to render leads.
    create_table :team_officers do |t|
      t.bigint :guild_id, null: false
      t.integer :team_id, null: false
      t.bigint :discord_user_id, null: false
      t.string :discord_username, default: "", null: false
      t.timestamps

      t.index :guild_id
      t.index %i[team_id discord_user_id], unique: true
    end
    add_foreign_key :team_officers, :guilds
    add_foreign_key :team_officers, :teams
  end
end
