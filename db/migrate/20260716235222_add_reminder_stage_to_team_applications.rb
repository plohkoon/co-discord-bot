class AddReminderStageToTeamApplications < ActiveRecord::Migration[8.1]
  def change
    # How many escalating pending-review reminders have been sent (0..3).
    add_column :team_applications, :reminder_stage, :integer, default: 0, null: false
  end
end
