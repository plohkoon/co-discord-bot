# Reconcile every posted roster with reality: rebuild each directory from the
# active teams its RosterPost covers (new teams appear, category/position moves
# land in the right message — or the right channel, when a team changes to a
# category another roster shows) and reflow it over that post's messages — edit
# in place, post extras when the directory grew, delete leftovers when it
# shrank. Enqueued by anything that changes what the roster shows. No-op until
# /guild roster has been posted once.
class RosterRefreshJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  def perform(guild_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      posts = RosterPost.all.to_a
      next if posts.empty?

      teams = Team.active.includes(:team_category, :team_type, :team_officers).to_a
      posts.each do |post|
        reflow(api, post, post.teams_from(teams))
      rescue Discord::BotApi::NotFound
        # The channel is gone (or the bot lost it) — forget this roster so
        # future edits stop trying.
        post.destroy
      end
    end
  end

  private

  def reflow(api, post, teams)
    colors = CoBot::RosterMessage.role_colors(api, teams)
    payloads = CoBot::RosterMessage.payloads(teams, colors)
    pending = post.message_ids.dup
    kept = []

    payloads.each do |payload, _included|
      message_id = pending.shift
      message_id = nil unless message_id && edit(api, post.channel_id, message_id, payload)
      kept << (message_id || api.create_message(post.channel_id, payload)["id"].to_i)
    end

    while (message_id = pending.first)
      begin
        api.delete_message(post.channel_id, message_id)
      rescue Discord::BotApi::NotFound
        nil # already gone
      end
      pending.shift
    end
  ensure
    # Record progress even when a call fails midway, so the retry edits what
    # was already posted instead of posting it twice.
    post.update!(message_ids: kept + pending) if kept && !post.destroyed?
  end

  # False when the message was deleted by hand — the caller posts fresh.
  def edit(api, channel_id, message_id, payload)
    api.edit_message(channel_id, message_id, payload)
    true
  rescue Discord::BotApi::NotFound
    false
  end
end
