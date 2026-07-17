# Reconcile the guild's posted roster with reality: rebuild the directory from
# every active team (new teams appear, category/position moves land in the
# right message) and reflow it over the existing messages — edit in place, post
# extras when the directory grew, delete leftovers when it shrank. Enqueued by
# anything that changes what the roster shows. No-op until /team roster has
# been posted once.
class RosterRefreshJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      teams = Team.active.includes(:team_category, :team_type, :team_officers).to_a

      # Messages come from ALL teams' recorded ids (a message whose teams went
      # inactive must still be reclaimed), newest channel wins (snowflakes
      # sort by time).
      tracked = Team.where.not(roster_channel_id: nil).where.not(roster_message_id: nil)
      newest = tracked.order(:roster_message_id).last or next
      channel_id = newest.roster_channel_id
      existing_ids = tracked.where(roster_channel_id: channel_id)
                            .distinct.pluck(:roster_message_id).sort

      begin
        reflow(api, channel_id, existing_ids, teams)
        # Teams no longer in the directory shouldn't keep pointing at it.
        Team.where.not(id: teams.map(&:id))
            .update_all(roster_channel_id: nil, roster_message_id: nil, updated_at: Time.current)
      rescue Discord::BotApi::NotFound
        # The channel is gone (or the bot lost it) — forget the roster so
        # future edits stop trying.
        Team.where.not(roster_message_id: nil)
            .update_all(roster_channel_id: nil, roster_message_id: nil, updated_at: Time.current)
      end
    end
  end

  private

  def reflow(api, channel_id, existing_ids, teams)
    colors = CoBot::RosterMessage.role_colors(api, teams)
    payloads = CoBot::RosterMessage.payloads(teams, colors)

    payloads.each_with_index do |(payload, included), index|
      message_id = existing_ids[index]
      message_id = nil unless message_id && edit(api, channel_id, message_id, payload)
      message_id ||= api.create_message(channel_id, payload)["id"]

      Team.where(id: included.map(&:id))
          .update_all(roster_channel_id: channel_id, roster_message_id: message_id, updated_at: Time.current)
    end

    existing_ids.drop(payloads.size).each do |message_id|
      api.delete_message(channel_id, message_id)
    rescue Discord::BotApi::NotFound
      nil # already gone
    end
  end

  # False when the message was deleted by hand — the caller posts fresh.
  def edit(api, channel_id, message_id, payload)
    api.edit_message(channel_id, message_id, payload)
    true
  rescue Discord::BotApi::NotFound
    false
  end
end
