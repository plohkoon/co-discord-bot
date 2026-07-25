class CreateAbsences < ActiveRecord::Migration[8.1]
  def change
    create_table :absences do |t|
      t.bigint :guild_id, null: false
      t.references :team, null: false, foreign_key: true # integer FK (teams has an integer PK)
      t.integer :team_membership_id # the person's active membership, when known
      t.bigint :discord_user_id, null: false # who is out
      t.string :discord_username, null: false, default: ""
      t.date :absence_on, null: false # the day they'll miss
      t.text :note
      t.bigint :created_by_discord_id, null: false
      t.integer :status, null: false, default: 0 # enum: 0 active, 1 cancelled
      t.datetime :cancelled_at
      t.bigint :cancelled_by_discord_id # nil = system cancellation (departed member)

      t.timestamps
    end

    add_index :absences, :guild_id
    add_index :absences, [ :team_id, :absence_on ]
    add_index :absences, [ :discord_user_id, :absence_on ]
    # At most one ACTIVE call-out per user per team per day (mirrors the
    # one-pending-application index).
    add_index :absences, [ :team_id, :discord_user_id, :absence_on ],
              unique: true, where: "status = 0",
              name: "index_absences_one_active_per_user_team_day"

    add_foreign_key :absences, :guilds, column: :guild_id, primary_key: :id
    add_foreign_key :absences, :team_memberships
  end
end
