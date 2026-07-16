class CreateTeams < ActiveRecord::Migration[8.1]
  def change
    create_table :teams do |t|
      t.bigint  :guild_id, null: false
      t.string  :name, null: false
      t.bigint  :team_role_id, null: false      # role granted on accept
      t.bigint  :officer_role_id, null: false   # role pinged to review applications
      t.bigint  :review_channel_id, null: false # channel applications are posted to
      t.text    :description
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :teams, :guild_id
    add_index :teams, [ :guild_id, :name ], unique: true
    add_foreign_key :teams, :guilds, column: :guild_id, primary_key: :id
  end
end
