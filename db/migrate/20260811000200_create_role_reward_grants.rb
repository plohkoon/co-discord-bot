class CreateRoleRewardGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :role_reward_grants do |t|
      t.integer :role_reward_id, null: false
      t.bigint :discord_user_id, null: false
      t.datetime :granted_at, null: false

      t.timestamps
    end

    # One grant per person per rule — the sweep checks this before spending a
    # REST call, so an already-rewarded member costs nothing on later passes.
    add_index :role_reward_grants, %i[role_reward_id discord_user_id], unique: true
    add_foreign_key :role_reward_grants, :role_rewards
  end
end
