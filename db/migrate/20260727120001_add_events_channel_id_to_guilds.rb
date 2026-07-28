class AddEventsChannelIdToGuilds < ActiveRecord::Migration[8.1]
  def change
    # Where scheduled-event announcements land. Nil = the feature is off for
    # this guild; nothing is posted and nothing is tracked.
    add_column :guilds, :events_channel_id, :bigint
  end
end
