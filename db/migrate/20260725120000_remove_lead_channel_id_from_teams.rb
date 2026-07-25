class RemoveLeadChannelIdFromTeams < ActiveRecord::Migration[8.1]
  def change
    # Absence call-outs are announced in the team's review channel — the same
    # place its applications land. A separate per-team "lead channel" was one
    # more thing to configure for no gain, so the setting is gone.
    remove_column :teams, :lead_channel_id, :bigint
  end
end
