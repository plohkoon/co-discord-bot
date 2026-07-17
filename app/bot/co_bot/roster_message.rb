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
    CONTAINER    = 17
    BUTTON       = 2

    # Discord caps a message at 40 components (nested ones count) and 4000
    # combined text-display characters; leave headroom.
    MAX_COMPONENTS = 38
    MAX_CHARS = 3800

    module_function

    # Post the directory, splitting into further messages only when a budget
    # overflows. Records each team's message so edits can repaint it.
    def post(api:, channel_id:, teams:)
      colors = role_colors(api, teams)
      payloads(teams, colors).each do |payload, included_teams|
        message = api.create_message(channel_id, payload)
        included_teams.each do |team|
          team.update(roster_channel_id: channel_id, roster_message_id: message["id"])
        end
      end
    end

    # One unchunked payload for repainting an existing message in place.
    def refresh_payload(teams, colors = {})
      components = []
      grouped(teams).each do |category, group|
        components << separator if category && components.any?
        components << header(category) if category
        group.each { |team| components << team_container(team, colors) }
      end
      payload_for(components)
    end

    # The teams' role colors ({role id (string) => integer}) — the accent
    # border of each team's container. One REST call; failures mean plain
    # borders, never a failed roster.
    def role_colors(api, teams)
      guild_id = teams.first&.guild_id
      return {} unless guild_id

      api.guild_roles(guild_id).to_h { |role| [ role["id"].to_s, role["color"].to_i ] }
    rescue Discord::BotApi::Error => e
      Rails.logger.warn("[roster] fetching role colors failed for guild #{guild_id}: #{e.class}: #{e.message}")
      {}
    end

    # [[payload, [team, ...]], ...] respecting the component/char budgets.
    def payloads(teams, colors = {})
      messages = []
      current = { components: [], chars: 0, teams: [] }

      grouped(teams).each do |category, group|
        header_pending = category
        group.each do |team|
          section = team_container(team, colors)
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

    # Categories in position order; teams by position (then name) within one;
    # uncategorized teams last, headerless.
    def grouped(teams)
      teams.group_by(&:team_category)
           .sort_by { |category, _| category ? [ 0, category.position, category.id ] : [ 1, 0, 0 ] }
           .map { |category, group| [ category, group.sort_by { |t| [ t.position, t.name.downcase ] } ] }
    end

    def team_block(team)
      lead_ids = team.team_officers.ordered.pluck(:discord_user_id)
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

    # Each team lives in a container whose accent color (the left border) is
    # its team role's color — 0 (Discord's "no color") renders borderless.
    def team_container(team, colors)
      color = colors[team.team_role_id.to_s].to_i
      {
        "type" => CONTAINER,
        "accent_color" => (color if color.positive?),
        "components" => [ team_section(team) ]
      }
    end

    def team_section(team)
      {
        "type" => SECTION,
        "components" => [ { "type" => TEXT_DISPLAY, "content" => team_block(team) } ],
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

    # Nested components count toward Discord's 40-component cap: a section is
    # 3 (itself + text child + button accessory), a container adds 1 around
    # whatever it holds.
    def component_cost(list)
      list.sum do |c|
        case c["type"]
        when CONTAINER then 1 + component_cost(c["components"])
        when SECTION   then 3
        else 1
        end
      end
    end

    def char_cost(list)
      list.sum do |c|
        case c["type"]
        when TEXT_DISPLAY then c["content"].size
        when CONTAINER    then char_cost(c["components"])
        else Array(c["components"]).sum { |child| child["content"].to_s.size }
        end
      end
    end

    def overflows?(current, addition)
      component_cost(current[:components]) + component_cost(addition) > MAX_COMPONENTS ||
        current[:chars] + char_cost(addition) > MAX_CHARS
    end
  end
end
