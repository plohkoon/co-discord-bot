class AddSlugToTeams < ActiveRecord::Migration[8.1]
  # Human slug for the public team apply URL (/apply/:guild_slug/teams/:team_slug).
  # Unique per guild, derived from the team name at creation, never regenerated
  # on rename — only an explicit edit on the web team form changes it.
  class MigrationTeam < ActiveRecord::Base
    self.table_name = "teams"
  end

  def up
    add_column :teams, :slug, :string

    MigrationTeam.reset_column_information
    MigrationTeam.order(:id).each do |team|
      slug = SlugGenerator.call(
        team.name, fallback: "team",
        taken: ->(candidate) { MigrationTeam.where(guild_id: team.guild_id, slug: candidate).exists? }
      )
      team.update_columns(slug: slug)
    end

    add_index :teams, [ :guild_id, :slug ], unique: true
  end

  def down
    remove_index :teams, [ :guild_id, :slug ]
    remove_column :teams, :slug
  end
end
