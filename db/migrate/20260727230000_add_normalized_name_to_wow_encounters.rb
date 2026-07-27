class AddNormalizedNameToWowEncounters < ActiveRecord::Migration[8.1]
  # The Raider.io ↔ Warcraft Logs join was built on Blizzard's journal encounter
  # id, which both services publish. Raider.io does populate it. **Warcraft Logs
  # does not** — verified live: `journalID` is 0 for every encounter in every
  # zone checked, current and years old alike. The field exists in their schema
  # and is simply never filled in.
  #
  # Boss names, however, match almost exactly — 8 of 9 in the live tier, with
  # the ninth differing only by a comma ("Chimaerus, the Undreamt God" vs
  # "Chimaerus the Undreamt God"). Normalising punctuation and case takes that
  # to 9 of 9.
  #
  # So the join now prefers the journal id (rigorous, and still correct if
  # Warcraft Logs ever starts publishing it) and falls back to a normalised
  # name. Names are a weaker key than ids — a boss renamed between services
  # would silently miss — which is why the fallback is explicit and only ever
  # *annotates* an encounter Raider.io already told us about.
  def change
    add_column :wow_encounters, :normalized_name, :string
    add_index :wow_encounters, :normalized_name

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE wow_encounters
          SET normalized_name = LOWER(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name, ',', ''), '''', ''), '-', ' '), '.', ''), ':', '')
          )
          WHERE name IS NOT NULL
        SQL
      end
    end
  end
end
