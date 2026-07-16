# Every table scoped to a Discord guild. Uses acts_as_tenant so queries are
# auto-scoped to the current guild and guild_id is auto-filled on create — the
# current guild is set at the two entry points (web before_action, bot dispatch).
module GuildScoped
  extend ActiveSupport::Concern

  included do
    acts_as_tenant(:guild)
  end
end
