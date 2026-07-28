# Posts the "there's an event" announcement into the guild's events channel.
# Enqueued by GuildEvents::Sync when a scheduled event first appears (Discord
# posts nothing to a text channel on its own).
#
# Idempotent: an event that already has an announcement, has since ended, or
# whose guild no longer has an events channel is a no-op.
class GuildEventAnnounceJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, guild_event_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return
    channel_id = guild.events_channel_id or return

    ActsAsTenant.with_tenant(guild) do
      event = GuildEvent.live.find_by(id: guild_event_id) or next
      next if event.announced? || event.terminal?

      role_ids = Discord::RoleMentions.call(guild_id: guild.id, text: event.description, api: api)
      message = api.create_message(channel_id, CoBot::EventMessage.announcement(event, role_ids: role_ids))
      event.update!(channel_id: channel_id, announcement_message_id: message["id"])
    rescue Discord::BotApi::NotFound
      nil # channel gone or the bot lost access — nothing to retry
    end
  end
end
