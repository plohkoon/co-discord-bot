class CreateTeamApplications < ActiveRecord::Migration[8.1]
  def change
    # Named TeamApplication (not Application) to avoid colliding with Rails'
    # ApplicationRecord / ApplicationController family.
    create_table :team_applications do |t|
      t.references :team, null: false, foreign_key: true
      t.bigint   :guild_id, null: false
      t.bigint   :discord_user_id, null: false     # the applicant
      t.string   :discord_username, null: false, default: ""
      t.integer  :status, null: false, default: 0  # enum: 0 pending, 1 accepted, 2 rejected
      t.bigint   :review_channel_id
      t.bigint   :review_message_id                # the officer-review message (holds the buttons)
      t.bigint   :decided_by_discord_id
      t.datetime :decided_at

      t.timestamps
    end

    add_index :team_applications, :guild_id
    add_index :team_applications, :discord_user_id
    add_index :team_applications, [ :team_id, :discord_user_id, :status ]
    # At most one OPEN (pending) application per user per team.
    add_index :team_applications, [ :team_id, :discord_user_id ],
              unique: true, where: "status = 0",
              name: "index_team_applications_one_pending_per_user"
    add_foreign_key :team_applications, :guilds, column: :guild_id, primary_key: :id
  end
end
