class CreateTeamTypes < ActiveRecord::Migration[8.1]
  # Keep in sync with TeamType::DEFAULT_NAMES (inlined so the migration doesn't
  # depend on app code).
  DEFAULT_NAMES = [ "Normal Team", "Heroic Team", "Mythic Team", "PvP Team" ].freeze

  # Model stubs so the data pass doesn't depend on app models (acts_as_tenant
  # scoping, future renames).
  class MigrationGuild < ActiveRecord::Base; self.table_name = "guilds"; end
  class MigrationTeamType < ActiveRecord::Base; self.table_name = "team_types"; end
  class MigrationTeam < ActiveRecord::Base; self.table_name = "teams"; end

  def up
    create_table :team_types do |t|
      t.bigint :guild_id, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.timestamps

      t.index :guild_id
      t.index %i[guild_id name], unique: true
    end
    add_foreign_key :team_types, :guilds

    add_column :teams, :team_type_id, :integer
    add_index :teams, :team_type_id
    add_foreign_key :teams, :team_types

    MigrationTeamType.reset_column_information
    MigrationTeam.reset_column_information

    # Every existing guild gets the stock list (new guilds are seeded by
    # Guild.sync_from_discord), then each team's old free-form team_type text
    # maps onto a type row — creating extra rows for values outside the stock
    # list so nothing is lost.
    MigrationGuild.pluck(:id).each do |guild_id|
      DEFAULT_NAMES.each_with_index do |name, i|
        MigrationTeamType.create!(guild_id: guild_id, name: name, position: i + 1)
      end
    end

    MigrationTeam.where.not(team_type: [ nil, "" ]).find_each do |team|
      label = team.team_type.strip
      next if label.blank?

      scope = MigrationTeamType.where(guild_id: team.guild_id)
      type = scope.where("LOWER(name) = ?", label.downcase).first ||
             scope.create!(name: label, position: scope.maximum(:position).to_i + 1)
      team.update_columns(team_type_id: type.id)
    end

    remove_column :teams, :team_type
  end

  def down
    add_column :teams, :team_type, :text
    execute <<~SQL
      UPDATE teams
      SET team_type = (SELECT name FROM team_types WHERE team_types.id = teams.team_type_id)
      WHERE team_type_id IS NOT NULL
    SQL

    remove_foreign_key :teams, :team_types
    remove_index :teams, :team_type_id
    remove_column :teams, :team_type_id
    drop_table :team_types
  end
end
