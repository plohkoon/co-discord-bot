class AddRemovedAtToGuilds < ActiveRecord::Migration[8.1]
  def change
    add_column :guilds, :removed_at, :datetime
  end
end
