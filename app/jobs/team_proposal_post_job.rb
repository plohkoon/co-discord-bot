# Posts a TeamProposal to the guild's team-proposals channel — enqueued by
# Components::ProposeTeamModal once the proposal is saved.
#
# The channel is re-resolved at run time, so one moved since the submit still
# wins, and one cleared leaves the proposal saved but unposted (readable in
# /admin). A category toggled off or deleted since doesn't stop the post: the
# pitch was valid when it was made. A recorded message id makes re-delivery a
# no-op. A missing channel or permission problem is logged, not retried
# (retrying can't fix it); only transient Discord errors retry.
class TeamProposalPostJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 3

  COLOR = 0xFFD166

  def perform(guild_id:, proposal_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      proposal = TeamProposal.find_by(id: proposal_id) or next
      next if proposal.posted?

      channel_id = guild.team_proposals_channel_id
      unless channel_id
        Rails.logger.warn("[team_proposals] proposal #{proposal.id} not posted: no team-proposals channel set")
        next
      end

      begin
        message = api.create_message(channel_id, payload(proposal))
        proposal.update!(channel_id: channel_id, message_id: message["id"].to_i)
      rescue Discord::BotApi::NotFound => e # covers Forbidden (a subclass)
        Rails.logger.warn("[team_proposals] proposal #{proposal.id} post failed: #{e.class}: #{e.message}")
      end
    end
  end

  private

  def payload(proposal)
    fields = proposal.answers.map do |entry|
      { "name" => entry["label"].to_s, "value" => entry["answer"].presence || "—", "inline" => false }
    end

    {
      "embeds" => [ {
        "title" => [ "New team proposal", proposal.team_category&.name ].compact.join(" — "),
        "description" => "From <@#{proposal.discord_user_id}> (#{proposal.discord_username})",
        "color" => COLOR,
        "fields" => fields,
        "timestamp" => proposal.created_at.iso8601
      } ],
      # The proposer's mention renders as a clickable name but pings no one.
      "allowed_mentions" => { "parse" => [] }
    }
  end
end
