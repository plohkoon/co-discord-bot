class CreateAbsenceDigests < ActiveRecord::Migration[8.1]
  def change
    # One durable row per (team, day) = "a grouped morning reminder is scheduled
    # for this team on this day". The timer itself lives in Solid Queue (an
    # exact-timestamp AbsenceDigestJob); this row makes the fire idempotent.
    create_table :absence_digests do |t|
      t.bigint  :guild_id, null: false
      t.integer :team_id, null: false
      t.date    :digest_on, null: false
      t.integer :status, null: false, default: 0  # enum: 0 pending, 1 sent
      t.datetime :sent_at
      t.bigint  :lead_channel_id
      t.bigint  :lead_message_id

      t.timestamps
    end

    add_index :absence_digests, :guild_id
    add_index :absence_digests, [ :team_id, :digest_on ], unique: true

    add_foreign_key :absence_digests, :guilds, column: :guild_id, primary_key: :id
    add_foreign_key :absence_digests, :teams
  end
end
