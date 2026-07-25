module Commands
  module Components
    # The /team absence modal submission. Parses the requested day (in the
    # guild's time zone) then records the call-out via Absences::Create, which
    # pings the leads and DM-confirms the requester. Key stays "callout" (the
    # optional persistent AbsenceButton is a future add).
    class AbsenceModal < Commands::Base
      component :modal, "callout", params: [ :team_id ]

      def call
        team = current_guild.teams.active.find_by(id: params[:team_id])
        return respond("That team no longer exists.") unless team

        absence_on = Absences::DateParser.call(event.value("day"), time_zone: current_guild.tz)
        note = event.value("note").to_s.strip.presence

        Absences::Create.call(team: team, event: event, absence_on: absence_on, note: note)
        respond("✅ Called out for **#{team.name}** on #{absence_on.to_fs(:long)} — leads notified.")
      rescue Absences::DateParser::Invalid => e
        respond("⚠️ #{e.message}")
      rescue Absences::Create::DuplicateAbsence
        respond("You've already called out of **#{team.name}** for that day.")
      rescue Absences::Create::NotOnTeam
        respond("You're not an active member of **#{team.name}**, so there's nothing to call out of.")
      end
    end
  end
end
