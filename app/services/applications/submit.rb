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
          source: :applied
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
      # write transaction): reminders at 24h/3d/6d + auto-reject at 7 days.
      Timeline.schedule(application)
      application
    rescue ActiveRecord::RecordNotUnique
      # The partial-unique index rejected a second pending application.
      raise DuplicatePending
    end

    private

    def user_id = @event.user.id

    def username
      user = @event.user
      # Discord's unique-username migration: discriminator is "0", so prefer the
      # global username over the legacy name#discriminator form.
      user.respond_to?(:username) ? user.username.to_s : user.to_s
    end
  end
end
