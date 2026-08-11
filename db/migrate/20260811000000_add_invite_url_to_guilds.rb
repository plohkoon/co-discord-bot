class AddInviteUrlToGuilds < ActiveRecord::Migration[8.1]
  # The public apply page shows a "Join this server" button to signed-in
  # visitors who aren't members yet. Discord invites live outside anything the
  # bot can read reliably (invites are per-channel and revocable), so the URL
  # is a Manage Server setting on the guild instead of something we derive.
  def change
    add_column :guilds, :invite_url, :string
  end
end
