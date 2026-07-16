class CreateGuilds < ActiveRecord::Migration[8.1]
  def change
    # A Discord server the bot is in. The primary key IS the Discord guild
    # snowflake, so `guild_id` on every other table literally holds the guild's
    # Discord id — no translation needed when handling gateway events.
    create_table :guilds, id: false do |t|
      t.bigint :id, null: false
      t.string :name, null: false, default: ""

      t.timestamps
    end
    add_index :guilds, :id, unique: true
  end
end
