# Posts the "come join in" nudge when a scheduled event goes ACTIVE. Discord
# only pushes a notification to members who clicked Interested, so this is the
# part everyone else ever sees.
#
# Idempotent: one start post per event, and never one for an event that already
# finished (a backstop can observe start and end in the same re-fetch).
class GuildEventStartJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, guild_event_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      event = GuildEvent.live.find_by(id: guild_event_id) or next
      next if event.start_posted? || event.terminal?

      channel_id = event.channel_id || guild.events_channel_id or next

      role_ids = Discord::RoleMentions.call(guild_id: guild.id, text: event.description, api: api)
      message = api.create_message(channel_id, CoBot::EventMessage.starting(event, role_ids: role_ids))
      event.update!(channel_id: channel_id, start_message_id: message["id"])
    rescue Discord::BotApi::NotFound
      nil # channel gone — nothing to retry
    end
  end
end
