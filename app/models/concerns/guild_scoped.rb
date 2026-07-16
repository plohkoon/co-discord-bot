# Shared behaviour for every table scoped to a Discord guild. `guild_id` holds
# the guild's Discord snowflake (== guilds.id).
module GuildScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :guild
    validates :guild_id, presence: true
    scope :for_guild, ->(guild_id) { where(guild_id: guild_id) }
  end
end
