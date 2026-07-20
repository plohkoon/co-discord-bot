class AddLogChannelsToGuilds < ActiveRecord::Migration[8.1]
  def change
    # Two optional log channels per guild (Discord snowflakes — bigint, never
    # integer). `important_log_channel_id` is the high-priority channel owners
    # watch; `log_channel_id` is the mundane audit trail. Either alone receives
    # everything (Guild#log_channel_id_for collapses the pair).
    add_column :guilds, :log_channel_id, :bigint
    add_column :guilds, :important_log_channel_id, :bigint
  end
end
