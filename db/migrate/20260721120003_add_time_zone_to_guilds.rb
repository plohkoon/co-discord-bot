class AddTimeZoneToGuilds < ActiveRecord::Migration[8.1]
  def change
    # The guild's local time zone — used to interpret call-out days and to fire
    # the morning absence digest at a sensible local hour. UTC until a manager
    # sets it on the web guild page.
    add_column :guilds, :time_zone, :string, null: false, default: "UTC"
  end
end
