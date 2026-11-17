require "test_helper"

module Applications
  # Choice questions answered through the Discord modal: the radio group sends
  # a string, the checkbox group an array, the checkbox a boolean — each stored
  # as the readable text officers see in the review message.
  class SubmitChoicesTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    FakeUser = Struct.new(:id, :username)

    # Shaped like discordrb's ModalSubmitEvent: value(key) / values(key).
    class FakeModalSubmit
      attr_reader :user

      def initialize(answers)
        @user = FakeUser.new(11, "alice")
        @answers = answers
      end

      def value(key) = @answers[key.to_s]
      def values(key) = @answers[key.to_s]
    end

    setup do
      @guild = Guild.sync_from_discord(id: 1, name: "Test")
      ActsAsTenant.with_tenant(@guild) do
        @team = Team.create!(name: "Alpha", team_role_id: 5, officer_role_id: 6, review_channel_id: 7)
        @role = @team.application_questions.create!(position: 0, key: "role", label: "Main role",
                                                    style: :choice, options_text: "Tank\nHealer\nDPS")
        @days = @team.application_questions.create!(position: 1, key: "days", label: "Raid days",
                                                    style: :checkboxes, options_text: "Tue\nWed\nThu")
        @rules = @team.application_questions.create!(position: 2, key: "rules", label: "Read the rules?",
                                                     style: :yes_no)
      end
    end

    def answers_for(submission)
      ActsAsTenant.with_tenant(@guild) do
        Submit.call(team: @team, event: submission).application_answers.order(:position).map do |a|
          [ a.question_label, a.answer ]
        end
      end
    end

    test "each choice style is stored as readable text" do
      answers = answers_for(FakeModalSubmit.new(
        "q:#{@role.id}" => "Healer", "q:#{@days.id}" => %w[Thu Tue], "q:#{@rules.id}" => true
      ))

      assert_equal [ [ "Main role", "Healer" ], [ "Raid days", "Tue, Thu" ], [ "Read the rules?", "Yes" ] ], answers
    end

    test "an unticked yes/no is an explicit No, and empty choices store blank" do
      answers = answers_for(FakeModalSubmit.new(
        "q:#{@role.id}" => nil, "q:#{@days.id}" => [], "q:#{@rules.id}" => false
      ))

      assert_equal [ [ "Main role", "" ], [ "Raid days", "" ], [ "Read the rules?", "No" ] ], answers
    end

    test "the web form's submission stores the same answers as the modal" do
      user = Struct.new(:discord_id, :username).new(11, "alice")
      answers = answers_for(WebSubmission.new(user: user, values: {
        "q:#{@role.id}" => "Healer", "q:#{@days.id}" => %w[Thu Tue], "q:#{@rules.id}" => "1"
      }))

      assert_equal [ [ "Main role", "Healer" ], [ "Raid days", "Tue, Thu" ], [ "Read the rules?", "Yes" ] ], answers
    end
  end
end
