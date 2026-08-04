class AddCharacterResolvedAtToApplications < ActiveRecord::Migration[8.1]
  # `character_input` present with no `wow_character_id` was doing double duty:
  # it meant both "we haven't looked yet" and "we looked and there's no such
  # character". Those need to read completely differently to an officer —
  # "Loading…" versus "Cannot load raider data" — and resolution is
  # asynchronous, so the ambiguous window is every application's first seconds.
  #
  # Stamped when ApplicationCharacterJob finishes, whichever way it went. The
  # three columns now encode four states unambiguously:
  #
  #   input nil                          → the team doesn't ask
  #   input, resolved_at nil             → still looking
  #   input, resolved_at set, id nil     → no such character (a typo)
  #   input, id present                  → resolved
  def change
    add_column :team_applications, :character_resolved_at, :datetime

    # Existing rows predate the character field entirely, so there is nothing
    # in flight to misread.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE team_applications SET character_resolved_at = updated_at
          WHERE character_input IS NOT NULL
        SQL
      end
    end
  end
end
