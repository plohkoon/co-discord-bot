module Applications
  # Records a team application + its answers. Runs inside the current-guild
  # tenant, so guild_id is auto-filled. Snapshots each question's key + label
  # onto the answer so it stays readable if questions change later.
  class Submit
    class DuplicatePending < StandardError; end

    def self.call(...) = new(...).call

    def initialize(team:, event:)
      @team = team
      @event = event
    end

    def call
      TeamApplication.transaction do
        application = @team.team_applications.create!(
          discord_user_id: @event.user.id,
          discord_username: username
        )

        @team.application_questions.ordered.each_with_index do |question, i|
          application.application_answers.create!(
            position: i,
            question_key: question.key,
            question_label: question.label,
            answer: @event.value("q:#{question.id}").to_s
          )
        end

        application
      end
    rescue ActiveRecord::RecordNotUnique
      # The partial-unique index rejected a second pending application.
      raise DuplicatePending
    end

    private

    def username
      user = @event.user
      # Discord's unique-username migration: discriminator is "0", so prefer the
      # global username over the legacy name#discriminator form.
      user.respond_to?(:username) ? user.username.to_s : user.to_s
    end
  end
end
