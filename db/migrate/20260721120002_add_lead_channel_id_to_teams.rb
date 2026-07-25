class AddLeadChannelIdToTeams < ActiveRecord::Migration[8.1]
  def change
    # Where absence call-outs are announced. Defaults (via Team#notify_channel_id)
    # to the review channel when blank.
    add_column :teams, :lead_channel_id, :bigint
  end
end
