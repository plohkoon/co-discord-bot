class AddPauseToTeamApplications < ActiveRecord::Migration[8.0]
  def change
    # Parked by a lead: status stays `pending` (so the one-pending-per-person
    # index and every pending? guard hold), but the daily digest skips it and
    # its 7-day deadline stops running.
    add_column :team_applications, :paused_at, :datetime
    add_column :team_applications, :paused_by_discord_id, :bigint

    # When the review clock started. Null = created_at; resuming a paused
    # application restarts the clock and stamps this. It's what both the
    # "waiting N days" line and the auto-reject deadline measure from.
    add_column :team_applications, :timeline_started_at, :datetime

    # The daily sweep derives everything it needs from the rows themselves, so
    # there's no per-application reminder bookkeeping left to keep.
    remove_column :team_applications, :reminder_stage, :integer, default: 0, null: false
  end
end
