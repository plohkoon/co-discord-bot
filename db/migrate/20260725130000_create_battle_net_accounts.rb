class CreateBattleNetAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :battle_net_accounts do |t|
      t.references :user, null: false, foreign_key: true
      # Blizzard's account id from the OIDC userinfo endpoint. Stable; the
      # BattleTag is not (users can change it), so never key off battle_tag.
      t.bigint :battle_net_id, null: false
      t.string :battle_tag
      # us | eu | kr | tw — decides which API host and namespace to query.
      t.string :region, null: false
      t.datetime :linked_at, null: false
      t.datetime :characters_synced_at

      t.timestamps
    end

    # A user may link more than one Battle.net account (alt accounts are common);
    # the same Blizzard account may not be linked twice to the same user.
    add_index :battle_net_accounts, %i[user_id battle_net_id], unique: true
    add_index :battle_net_accounts, :battle_net_id
  end
end
