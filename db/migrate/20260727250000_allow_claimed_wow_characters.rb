class AllowClaimedWowCharacters < ActiveRecord::Migration[8.1]
  # A character belongs to a USER, not to a Battle.net account.
  #
  # Until now the only way a character could exist was through the OAuth link,
  # which made `battle_net_account_id` mandatory and left anyone unwilling or
  # unable to link invisible to the whole WoW pipeline. That's the wrong
  # requirement for an application flow: an applicant should be able to say
  # "this is my character" and have a reviewer see their gear and parses,
  # whether or not they've authorised anything.
  #
  # So ownership moves to `user_id` and the Battle.net account becomes
  # *evidence* rather than the relationship itself:
  #
  #   verified_at present  → Blizzard confirmed they own it (OAuth)
  #   claimed_at present   → the user asserted it, unproven
  #
  # Those are deliberately separate columns rather than one status, because a
  # claim that is later verified is both, and the distinction is exactly what a
  # reviewer needs to weigh.
  def change
    add_reference :wow_characters, :user, foreign_key: true, index: true
    add_column :wow_characters, :claimed_at, :datetime
    # Region was delegated from the Battle.net account. It's a property of the
    # character's realm, not of the account, and a claimed character has no
    # account to delegate to.
    add_column :wow_characters, :region, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE wow_characters
          SET user_id = (
                SELECT battle_net_accounts.user_id FROM battle_net_accounts
                WHERE battle_net_accounts.id = wow_characters.battle_net_account_id
              ),
              region = (
                SELECT battle_net_accounts.region FROM battle_net_accounts
                WHERE battle_net_accounts.id = wow_characters.battle_net_account_id
              )
          WHERE battle_net_account_id IS NOT NULL
        SQL
      end
    end

    change_column_null :wow_characters, :battle_net_account_id, true

    # A character is one real thing in the world, so it gets one row: Blizzard's
    # character id is globally unique (verified — no duplicates across accounts).
    # Keying on it means a claim and a later OAuth verification converge on the
    # same row instead of forking, and stops the refresh jobs doing the same
    # work twice for two people who both point at one character.
    remove_index :wow_characters, column: %i[battle_net_account_id blizzard_id]
    add_index :wow_characters, :blizzard_id, unique: true
  end
end
