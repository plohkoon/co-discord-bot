class AddAboutAndProposalsToTeamCategories < ActiveRecord::Migration[8.1]
  # A category can now carry an "about" blurb under its roster header, and an
  # "Apply to make a team" button beside it. Proposals from every category go
  # to ONE admin channel on the guild; each category just opts in.
  def change
    add_column :team_categories, :about, :text
    add_column :team_categories, :proposals_enabled, :boolean, null: false, default: false
    add_column :guilds, :team_proposals_channel_id, :bigint

    create_table :team_proposals do |t|
      t.bigint :guild_id, null: false
      # Nullified, not cascaded, when the category is removed: the proposal is
      # still someone's pitch and the posted message still references it.
      t.integer :team_category_id
      t.bigint :discord_user_id, null: false
      t.string :discord_username, null: false, default: ""
      # JSON array of { "label", "answer" } pairs, captured verbatim with the
      # labels as asked, so a later wording change doesn't rewrite history.
      t.text :answers, null: false
      # Where the post landed. Set by TeamProposalPostJob; its presence is the
      # re-delivery guard.
      t.bigint :channel_id
      t.bigint :message_id
      t.timestamps

      t.index :guild_id
      t.index :team_category_id
    end
    add_foreign_key :team_proposals, :guilds
    add_foreign_key :team_proposals, :team_categories, on_delete: :nullify
  end
end
