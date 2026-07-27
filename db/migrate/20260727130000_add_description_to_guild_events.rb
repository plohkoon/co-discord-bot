class AddDescriptionToGuildEvents < ActiveRecord::Migration[8.1]
  def change
    # Mirrored so the posting jobs can scan it for role mentions. Never echoed
    # into a message — only resolved role ids are taken from it.
    add_column :guild_events, :description, :text
  end
end
