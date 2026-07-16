class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # Web-app users, identified by their Discord account. Not guild-scoped —
    # a user may manage several guilds.
    create_table :users do |t|
      t.bigint :discord_id, null: false
      t.string :username, null: false, default: ""
      t.string :global_name
      t.string :avatar

      t.timestamps
    end

    add_index :users, :discord_id, unique: true
  end
end
