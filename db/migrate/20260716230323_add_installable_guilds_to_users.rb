class AddInstallableGuildsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :installable_guilds, :text
  end
end
