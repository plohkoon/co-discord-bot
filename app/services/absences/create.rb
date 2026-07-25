module Absences
  # Records one call-out for a raider on a team, then (after commit) wires up the
  # notifications — mirrors Applications::Submit. Runs inside the current-guild
  # tenant so guild_id auto-fills. The caller must be an ACTIVE member of the
  # team (you can't call out of a team you're not on).
  class Create
    class DuplicateAbsence < StandardError; end
    class NotOnTeam < StandardError; end

    def self.call(...) = new(...).call

    def initialize(team:, event:, absence_on:, note: nil)
      @team = team
      @event = event
      @absence_on = absence_on
      @note = note.to_s.strip.presence
    end

    def call
      membership = @team.team_memberships.active.find_by(discord_user_id: user_id)
      raise NotOnTeam unless membership

      absence = Absence.transaction do
        Absence.create!(
          team: @team,
          team_membership: membership,
          discord_user_id: user_id,
          discord_username: username,
          absence_on: @absence_on,
          note: @note,
          created_by_discord_id: user_id
        )
      end

      # After the commit (the queue is a separate DB — never enqueue inside the
      # write transaction): make sure the team's grouped morning digest for that
      # day exists and is scheduled exactly once, ping the leads now, and
      # DM-confirm the requester (the pre-built kind: "absence" template).
      digest, created = ensure_digest(@absence_on)
      AbsenceDigest::Timeline.schedule(digest) if created
      AbsenceLeadNotifyJob.perform_later(guild_id: absence.guild_id, absence_id: absence.id)
      ConfirmationDmJob.perform_later(
        guild_id: absence.guild_id,
        team_id: @team.id,
        discord_user_id: user_id,
        kind: "absence"
      )
      absence
    rescue ActiveRecord::RecordNotUnique
      # The partial-unique index rejected a second active call-out for the same
      # user / team / day.
      raise DuplicateAbsence
    end

    private

    # Exactly one digest row (and one scheduled job) per team-day, even when a
    # second raider calls out for the same day: the unique [team_id, digest_on]
    # index + find_or_create_by! guarantees it; the concurrent-first-caller race
    # (both find nothing, both insert) surfaces as RecordNotUnique — refetch and
    # report "already existed" so we don't double-schedule.
    def ensure_digest(date)
      created = false
      digest = AbsenceDigest.find_or_create_by!(team: @team, digest_on: date) { created = true }
      [ digest, created ]
    rescue ActiveRecord::RecordNotUnique
      [ AbsenceDigest.find_by!(team: @team, digest_on: date), false ]
    end

    def user_id = @event.user.id

    def username
      user = @event.user
      user.respond_to?(:username) ? user.username.to_s : user.to_s
    end
  end
end
