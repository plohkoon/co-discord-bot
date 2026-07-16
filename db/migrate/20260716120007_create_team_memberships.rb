class CreateTeamMemberships < ActiveRecord::Migration[8.1]
  def change
    # The durable person x team relationship — the anchor for status + notes.
    # Applications are dated events that move a membership between states.
    create_table :team_memberships do |t|
      t.references :team, null: false, foreign_key: true
      t.bigint   :guild_id, null: false
      t.bigint   :discord_user_id, null: false
      t.string   :discord_username, null: false, default: ""
      t.integer  :status, null: false, default: 0  # 0 pending, 1 active, 2 archived
      t.datetime :joined_at
      t.datetime :left_at

      t.timestamps
    end

    add_index :team_memberships, [ :team_id, :discord_user_id ], unique: true
    add_index :team_memberships, :guild_id
    add_index :team_memberships, [ :team_id, :status ]
    add_foreign_key :team_memberships, :guilds, column: :guild_id, primary_key: :id
  end
end
