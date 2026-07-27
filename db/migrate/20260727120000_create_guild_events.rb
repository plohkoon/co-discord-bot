class CreateGuildEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :guild_events do |t|
      t.bigint :guild_id, null: false
      # The native Discord scheduled event this row mirrors. We never create
      # events ourselves — Discord's Events tab stays the source of truth.
      t.bigint :discord_event_id, null: false
      t.string :name, null: false, default: ""
      # Mirrors Discord's status enum verbatim (1 scheduled, 2 active,
      # 3 completed, 4 canceled) so a payload maps straight onto it.
      t.integer :status, null: false, default: 1
      t.datetime :scheduled_start_time
      t.datetime :scheduled_end_time

      # Where we posted, and what — cleared out again by the cleanup sweep.
      t.bigint :channel_id
      t.bigint :announcement_message_id
      t.bigint :start_message_id

      # When the event reached a terminal status (anchors the cleanup delay)
      # and when our posts were actually removed.
      t.datetime :ended_at
      t.datetime :cleaned_up_at

      t.timestamps
    end

    add_index :guild_events, [ :guild_id, :discord_event_id ], unique: true
  end
end
