class AddCharacterToApplicationsAndUsers < ActiveRecord::Migration[8.1]
  def change
    # --- The main character ---
    #
    # A linked account brings ~50 characters. Showing an officer all of them is
    # worse than showing the right one, so a person nominates a main.
    # Deliberately a pointer on the user rather than a flag on the character:
    # "exactly one" is then structural instead of something a callback has to
    # keep true.
    add_reference :users, :main_wow_character, foreign_key: { to_table: :wow_characters },
                  null: true, index: true

    # --- The character someone plays on a given team ---
    #
    # Separate from their main because it genuinely differs: people main a tank
    # and raid as a healer, or bring an alt to the second team. Seeded from the
    # application, changeable by the team's leads.
    add_reference :team_memberships, :wow_character, foreign_key: true, null: true, index: true

    # --- What the applicant typed ---
    #
    # `character_input` is kept verbatim alongside the resolved record, not
    # discarded on success, because it is the only evidence of what they meant
    # when resolution fails. The two columns together encode three states:
    #
    #   input nil                  → the team doesn't ask for a character
    #   input present, id nil      → typed something Blizzard doesn't recognise
    #   input present, id present  → resolved and claimed
    add_column :team_applications, :character_input, :string
    add_reference :team_applications, :wow_character, foreign_key: true, null: true, index: true

    # Whether the apply modal asks for a character at all, and where to look for
    # it. Region matters: "Thrall-Sargeras" names no region, and a EU guild
    # would otherwise have every application fail to resolve.
    add_column :teams, :collect_character, :boolean, null: false, default: true
    add_column :teams, :region, :string, null: false, default: "us"

    # The character input costs one of Discord's five modal slots. A team
    # already using all five would be pushed over the limit, so those opt out
    # rather than silently losing a question.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE teams SET collect_character = 0
          WHERE (SELECT COUNT(*) FROM application_questions
                 WHERE application_questions.team_id = teams.id) >= 5
        SQL
      end
    end
  end
end
