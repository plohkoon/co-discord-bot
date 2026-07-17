module CoBot
  # Builds and posts the /team roster directory: a header message per category,
  # then one message per team with its roster lines and an Apply button. Role
  # and user mentions render colored but ping nobody (allowed_mentions: none).
  #
  # Each team's message ids are recorded (roster_channel_id/roster_message_id)
  # so later edits to the team auto-refresh the block via TeamRosterRefreshJob.
  # team_block is transport-agnostic — the caller supplies the lead ids
  # (gateway role cache here, REST member pagination in the refresh job).
  module RosterMessage
    NO_MENTIONS = { parse: [] }.freeze

    module_function

    def post(server:, channel:, teams:)
      grouped(teams).each do |category, group|
        channel.send_message("## #{category.name}", false, nil, nil, NO_MENTIONS) if category
        group.each do |team|
          block = team_block(team, gateway_lead_ids(team, server))
          message = channel.send_message(block, false, nil, nil, NO_MENTIONS, nil, apply_view(team))
          team.update(roster_channel_id: channel.id, roster_message_id: message.id)
        end
      end
    end

    # Categories in position order; uncategorized teams last, headerless.
    def grouped(teams)
      teams.group_by(&:team_category)
           .sort_by { |category, _| category ? [ 0, category.position, category.id ] : [ 1, 0, 0 ] }
           .map { |category, group| [ category, group.sort_by { |t| t.name.downcase } ] }
    end

    def team_block(team, lead_ids)
      lines = [ "<@&#{team.team_role_id}>" ]
      summary = [
        team.team_type.presence && "*#{team.team_type}*",
        team.progression.presence,
        team.requirements.presence
      ].compact.join(" | ")
      lines << summary if summary.present?
      lines << "__Team Leads:__ #{lead_ids.any? ? lead_ids.map { |id| "<@#{id}>" }.join(' | ') : '—'}"
      lines << "__Date and Time:__ #{team.date_and_time.presence || '—'}"
      lines << "__Current Needs:__ #{team.current_needs.presence || '—'}"
      lines.join("\n")
    end

    # Leads = current holders of the team's officer role, read live from
    # Discord so the roster can never drift from reality.
    def gateway_lead_ids(team, server)
      role = server.role(team.officer_role_id)
      (role ? role.members.reject(&:bot_account?) : []).map(&:id)
    end

    def apply_view(team)
      view = Discordrb::Webhooks::View.new
      view.row do |row|
        row.button(label: "Apply — #{team.name}"[0, 80], style: :primary,
                   custom_id: CoBot::CommandRegistry.custom_id("applyto", team.id))
      end
      view
    end
  end
end
