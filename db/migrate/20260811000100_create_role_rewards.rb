class CreateRoleRewards < ActiveRecord::Migration[8.1]
  def change
    create_table :role_rewards do |t|
      t.bigint :guild_id, null: false
      t.bigint :discord_role_id, null: false
      # achievement | mythic_plus | pvp
      t.string :kind, null: false
      # kind=achievement: exact stored achievement name to match.
      t.string :achievement_name
      # kind=mythic_plus/pvp: minimum score/rating.
      t.integer :threshold
      # kind=pvp: restrict to one bracket type (2v2/3v3/rbg/shuffle/blitz);
      # nil = any rated bracket.
      t.string :pvp_bracket_type
      # Opt-in: strip the role again when the requirement stops holding
      # (e.g. scores reset at the end of a season). Default is grant-only.
      t.boolean :auto_revoke, null: false, default: false

      t.timestamps
    end

    add_index :role_rewards, :guild_id
    add_foreign_key :role_rewards, :guilds
  end
end
