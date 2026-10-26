class CreateRosterPosts < ActiveRecord::Migration[8.1]
  # A guild can now post several team directories — one per channel, each
  # optionally limited to some categories — so where a roster lives moves off
  # the team (which could only ever point at one) onto its own row.
  def up
    create_table :roster_posts do |t|
      t.bigint :guild_id, null: false
      t.bigint :channel_id, null: false
      # JSON array of team_category ids; NULL means every team, uncategorized
      # included.
      t.text :category_ids
      # JSON array of the directory's message ids, in display order (NULL
      # when empty — that's how a serialized empty Array is stored).
      t.text :message_ids
      t.timestamps

      t.index %i[guild_id channel_id], unique: true
    end
    add_foreign_key :roster_posts, :guilds

    # Carry the existing single roster over as an unfiltered post: the newest
    # channel any team points at, as RosterRefreshJob used to resolve it.
    rows = select_rows(<<~SQL)
      SELECT guild_id, roster_channel_id, roster_message_id FROM teams
      WHERE roster_channel_id IS NOT NULL AND roster_message_id IS NOT NULL
    SQL
    now = connection.quote(Time.current)
    rows.group_by(&:first).each do |guild_id, guild_rows|
      channel_id = guild_rows.max_by(&:last)[1]
      message_ids = guild_rows.select { |row| row[1] == channel_id }.map(&:last).uniq.sort
      execute(<<~SQL)
        INSERT INTO roster_posts (guild_id, channel_id, message_ids, created_at, updated_at)
        VALUES (#{guild_id.to_i}, #{channel_id.to_i}, #{connection.quote(message_ids.to_json)}, #{now}, #{now})
      SQL
    end

    remove_column :teams, :roster_channel_id
    remove_column :teams, :roster_message_id
  end

  def down
    add_column :teams, :roster_channel_id, :bigint
    add_column :teams, :roster_message_id, :bigint
    drop_table :roster_posts
  end
end
