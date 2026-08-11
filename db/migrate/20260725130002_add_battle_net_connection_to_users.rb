class AddBattleNetConnectionToUsers < ActiveRecord::Migration[8.1]
  # What Discord reports the user has linked on *their* side, refreshed at each
  # sign-in from /users/@me/connections. A hint for the link flow and a
  # cross-check against a real Battle.net link — never a substitute for one.
  #
  # The id is t.string, not bigint: it's Discord's opaque identifier for the
  # connection, and casting an unexpected non-numeric value would silently
  # turn it into 0 and make the cross-check quietly wrong.
  def change
    add_column :users, :discord_battle_net_id, :string
    add_column :users, :discord_battle_tag, :string
  end
end
