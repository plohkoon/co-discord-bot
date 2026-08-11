module Applications
  # Records a team application + its answers, routed through the applicant's
  # membership (created/reopened as needed). Runs inside the current-guild
  # tenant, so guild_id auto-fills. Snapshots each question's key + label onto
  # the answer so it stays readable if questions change later.
  class Submit
    class DuplicatePending < StandardError; end
    class AlreadyMember < StandardError; end

    def self.call(...) = new(...).call

    def initialize(team:, event:)
      @team = team
      @event = event
    end

    def call
      membership = TeamMembership.find_or_create_by!(team_id: @team.id, discord_user_id: user_id) do |m|
        m.discord_username = username
      end
      raise AlreadyMember if membership.active?

      application = TeamApplication.transaction do
        membership.update!(status: :pending, discord_username: username)

        record = membership.team_applications.create!(
          team: @team,
          discord_user_id: user_id,
          discord_username: username,
          source: :applied,
          # Stored verbatim and resolved out of band — see
          # ApplicationCharacterJob. A typo must never cost someone their
          # application, so nothing here validates it.
          character_input: character_input
        )

        @team.application_questions.ordered.each_with_index do |question, i|
          record.application_answers.create!(
            position: i,
            question_key: question.key,
            question_label: question.label,
            answer: @event.value("q:#{question.id}").to_s
          )
        end

        record
      end

      # After the commit (the queue is a separate DB — never enqueue inside the
      # write transaction): the guild log entry and the "you're on file" DM to
      # the applicant. Nothing time-based is scheduled here — the daily
      # ReviewDigestSweepJob reads the live rows, so there are no
      # per-application timers to go stale.
      # High-priority: owners want to know a new application arrived.
      GuildLog.record(
        guild: ActsAsTenant.current_tenant,
        level: :high,
        title: "Application received",
        description: "#{application.applicant_mention} applied to **#{@team.name}**.",
        color: 0x5865F2
      )
      # The officer review message (embed + persistent Accept/Reject buttons in
      # the team's review channel) posts out of band over REST — one shared
      # path whether the application came from the Discord modal or the public
      # web form.
      ReviewMessagePostJob.perform_later(guild_id: application.guild_id,
                                         application_id: application.id)
      # Resolving costs a Blizzard round trip, so it happens after the commit
      # and out of band: the officers are already notified and the applicant
      # already has their acknowledgement.
      if application.character_input.present?
        ApplicationCharacterJob.perform_later(application_id: application.id,
                                              guild_id: application.guild_id)
      end
      ConfirmationDmJob.perform_later(
        guild_id: application.guild_id,
        team_id: @team.id,
        discord_user_id: application.discord_user_id,
        kind: "apply"
      )
      application
    rescue ActiveRecord::RecordNotUnique
      # The partial-unique index rejected a second pending application.
      raise DuplicatePending
    end

    private

    def user_id = @event.user.id

    def character_input = @event.value("character").to_s.strip.presence

    def username
      user = @event.user
      # Discord's unique-username migration: discriminator is "0", so prefer the
      # global username over the legacy name#discriminator form.
      user.respond_to?(:username) ? user.username.to_s : user.to_s
    end
  end
end
