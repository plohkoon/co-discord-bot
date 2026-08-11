class NullifyWowCharacterReferencesOnDelete < ActiveRecord::Migration[8.1]
  # Deleting a character must not be blocked by the things pointing at it.
  #
  # Characters genuinely do go away — someone releases a claim, or unlinks the
  # Battle.net account that verified them. Without ON DELETE SET NULL that hits
  # a foreign key violation, so releasing your own main would simply fail.
  #
  # Nullify rather than cascade in every case: the reference disappearing must
  # not take the referrer with it. Losing a main should not delete the user;
  # losing the character someone raided on should not delete their membership
  # or, worse, their application.
  TABLES = {
    users: :main_wow_character_id,
    team_memberships: :wow_character_id,
    team_applications: :wow_character_id
  }.freeze

  def up
    TABLES.each do |table, column|
      remove_foreign_key table, to_table: :wow_characters, column: column
      add_foreign_key table, :wow_characters, column: column, on_delete: :nullify
    end
  end

  def down
    TABLES.each do |table, column|
      remove_foreign_key table, to_table: :wow_characters, column: column
      add_foreign_key table, :wow_characters, column: column
    end
  end
end
