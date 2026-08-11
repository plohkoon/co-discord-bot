class AddDescriptionToGuilds < ActiveRecord::Migration[8.0]
  # A short server blurb shown at the top of the public apply page, mirroring
  # the team bio (500-char cap enforced in the model). No backfill — and none
  # should ever loop over Guild rows with a table-only model here without
  # `self.primary_key = "id"` (the guilds table is `id: false`).
  def change
    add_column :guilds, :description, :text
  end
end
