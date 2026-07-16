class CreateMembershipNotes < ActiveRecord::Migration[8.1]
  def change
    # Officer-only notes on a membership; persist across re-applications.
    create_table :membership_notes do |t|
      t.references :team_membership, null: false, foreign_key: true
      t.bigint :guild_id, null: false
      t.bigint :author_discord_id, null: false
      t.string :author_username, null: false, default: ""
      t.text   :body, null: false, default: ""

      t.timestamps
    end

    add_index :membership_notes, :guild_id
    add_foreign_key :membership_notes, :guilds, column: :guild_id, primary_key: :id
  end
end
