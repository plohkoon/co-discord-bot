module Commands
  module Team
    # Post the public team directory: category headers, one block per team with
    # an Apply button. Leads are read live from the officer role's holders.
    class Roster < Commands::Base
      description "Post the team directory"
      channel :channel, "Channel to post in (default: here)", channel_types: [ :text ]
      admin_only!

      def call
        teams = current_guild.teams.active.includes(:team_category).to_a
        return respond("No active teams to list yet — `/team create` one first.") if teams.empty?

        channel = target_channel
        return respond("I can't find that channel.") unless channel

        # Ack first: listing role holders chunks the member list, which can
        # take seconds on large servers.
        respond("📋 Posting the team directory in <##{channel.id}>…")
        CoBot::RosterMessage.post(server: server, channel: channel, teams: teams)
      rescue Discordrb::Errors::NoPermission
        follow_up("⚠️ I couldn't post in <##{channel.id}> — I need **Send Messages** and **Embed Links** there. " \
                  "Grant them to my role (or re-run the invite link) and try `/team roster` again.")
      end

      private

      def target_channel
        id = option(:channel)
        id ? event.bot.channel(id) : event.channel
      end
    end
  end
end
