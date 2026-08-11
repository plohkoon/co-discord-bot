class AddSlugToGuilds < ActiveRecord::Migration[8.1]
  # Human slug for the public apply URLs (/apply/:guild_slug) instead of the
  # raw snowflake. Globally unique; derived from the server name at creation
  # and NEVER regenerated on rename (shared links must keep working) — only an
  # explicit edit on the guild settings page changes it.
  #
  # Table-only model so the migration doesn't depend on app-model callbacks or
  # validations; SlugGenerator is pure string logic.
  class MigrationGuild < ActiveRecord::Base
    self.table_name = "guilds"
    # guilds is created with `id: false` (the PK is the Discord snowflake,
    # declared as a plain bigint column), so Rails can't infer the primary
    # key — without this, update_columns builds `WHERE "guilds"."" = ...`.
    self.primary_key = "id"
  end

  def up
    add_column :guilds, :slug, :string

    MigrationGuild.reset_column_information
    MigrationGuild.order(:id).each do |guild|
      slug = SlugGenerator.call(guild.name, fallback: "guild",
                                taken: ->(candidate) { MigrationGuild.where(slug: candidate).exists? })
      guild.update_columns(slug: slug)
    end

    add_index :guilds, :slug, unique: true
  end

  def down
    remove_index :guilds, :slug
    remove_column :guilds, :slug
  end
end
