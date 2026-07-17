module CoBot
  # Builds the /team roster directory as Components-V2 messages: one seamless
  # message (or as few as Discord's budgets allow) with "## Category" headers,
  # a section per team, and each team's Apply button inline beside its block —
  # instead of a pile of separate messages.
  #
  # discordrb 3.8 predates Components V2, so payloads are raw hashes sent over
  # REST via Discord::BotApi — which also lets TeamRosterRefreshJob rebuild a
  # message identically from a worker process. Mentions render colored but
  # ping nobody (allowed_mentions: none).
  module RosterMessage
    FLAG_COMPONENTS_V2 = 1 << 15
    TEXT_DISPLAY = 10
    SECTION      = 9
    SEPARATOR    = 14
    BUTTON       = 2

    # Discord caps a message at 40 components (nested ones count) and 4000
    # combined text-display characters; leave headroom.
    MAX_COMPONENTS = 38
    MAX_CHARS = 3800

    module_function

    # Post the directory, splitting into further messages only when a budget
    # overflows. Records each team's message so edits can repaint it.
    def post(api:, channel_id:, teams:, lead_ids_by_team:)
      payloads(teams, lead_ids_by_team).each do |payload, included_teams|
        message = api.create_message(channel_id, payload)
        included_teams.each do |team|
          team.update(roster_channel_id: channel_id, roster_message_id: message["id"])
        end
      end
    end

    # One unchunked payload for repainting an existing message in place.
    def refresh_payload(teams, lead_ids_by_team)
      components = []
      grouped(teams).each do |category, group|
        components << separator if category && components.any?
        components << header(category) if category
        group.each { |team| components << team_section(team, lead_ids_by_team.fetch(team.id, [])) }
      end
      payload_for(components)
    end

    # [[payload, [team, ...]], ...] respecting the component/char budgets.
    def payloads(teams, lead_ids_by_team)
      messages = []
      current = { components: [], chars: 0, teams: [] }

      grouped(teams).each do |category, group|
        header_pending = category
        group.each do |team|
          section = team_section(team, lead_ids_by_team.fetch(team.id, []))
          addition = []
          if header_pending
            addition << separator if current[:components].any?
            addition << header(category)
          end
          addition << section

          if current[:teams].any? && overflows?(current, addition)
            messages << current
            current = { components: [], chars: 0, teams: [] }
            addition = (category ? [ header(category) ] : []) + [ section ]
          end

          current[:components].concat(addition)
          current[:chars] += char_cost(addition)
          current[:teams] << team
          header_pending = false
        end
      end

      messages << current if current[:teams].any?
      messages.map { |m| [ payload_for(m[:components]), m[:teams] ] }
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

    # Leads = current holders of the team's officer role, read live from the
    # gateway cache so the roster can never drift from reality.
    def gateway_lead_ids(team, server)
      role = server.role(team.officer_role_id)
      (role ? role.members.reject(&:bot_account?) : []).map(&:id)
    end

    def team_section(team, lead_ids)
      {
        "type" => SECTION,
        "components" => [ { "type" => TEXT_DISPLAY, "content" => team_block(team, lead_ids) } ],
        "accessory" => {
          "type" => BUTTON, "style" => 1, "label" => "Apply",
          "custom_id" => CoBot::CommandRegistry.custom_id("applyto", team.id)
        }
      }
    end

    def header(category)  = { "type" => TEXT_DISPLAY, "content" => "## #{category.name}" }
    def separator         = { "type" => SEPARATOR, "divider" => true, "spacing" => 2 }

    def payload_for(components)
      {
        "flags" => FLAG_COMPONENTS_V2,
        "components" => components,
        "allowed_mentions" => { "parse" => [] }
      }
    end

    # A section counts as 3 components (itself + text child + button accessory).
    def component_cost(list) = list.sum { |c| c["type"] == SECTION ? 3 : 1 }

    def char_cost(list)
      list.sum do |c|
        next c["content"].size if c["type"] == TEXT_DISPLAY

        Array(c["components"]).sum { |child| child["content"].to_s.size }
      end
    end

    def overflows?(current, addition)
      component_cost(current[:components]) + component_cost(addition) > MAX_COMPONENTS ||
        current[:chars] + char_cost(addition) > MAX_CHARS
    end
  end
end
