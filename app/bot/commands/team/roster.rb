module Commands
  module Team
    # Post the public team directory: one seamless Components-V2 message with
    # category headers and an inline Apply button beside each team. Leads are
    # read live from the officer role's holders.
    class Roster < Commands::Base
      description "Post the team directory"
      channel :channel, "Channel to post in (default: here)", channel_types: [ :text ]
      admin_only!

      def call
        teams = current_guild.teams.active.includes(:team_category).to_a
        return respond("No active teams to list yet — `/team create` one first.") if teams.empty?

        channel_id = option(:channel) || event.channel&.id
        return respond("I can't find that channel.") unless channel_id

        # Ack first: listing role holders chunks the member list, which can
        # take seconds on large servers.
        respond("📋 Posting the team directory in <##{channel_id}>…")

        lead_ids = teams.to_h { |team| [ team.id, CoBot::RosterMessage.gateway_lead_ids(team, server) ] }
        CoBot::RosterMessage.post(api: Discord::BotApi.new, channel_id: channel_id,
                                  teams: teams, lead_ids_by_team: lead_ids)
      rescue Discord::BotApi::Error
        follow_up("⚠️ I couldn't post in <##{channel_id}> — I need **Send Messages** there. " \
                  "Grant it to my role (or re-run the invite link) and try `/team roster` again.")
      end
    end
  end
end
