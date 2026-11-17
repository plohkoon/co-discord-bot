require "application_system_test_case"

# The application-question editor's style select shows only the settings that
# style uses (question_form_controller.js): a placeholder for text, an options
# box for multiple choice / checkboxes, and no Required toggle for yes/no.
class QuestionFormTest < ApplicationSystemTestCase
  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
    end
  end

  # Signs in through the mocked OAuth callback with the remote lookups stubbed,
  # then runs the test body inside the session.
  def signed_in_as_manager
    user = users(:member)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:discord] = OmniAuth::AuthHash.new(
      provider: "discord", uid: user.discord_id.to_s, info: { name: user.username },
      credentials: { token: "test-token" },
      extra: { raw_info: { "username" => user.username, "global_name" => user.global_name } }
    )
    result = Discord::ManageableGuilds::Result.new([ { "id" => @guild.id.to_s } ], [], [ @guild.id.to_s ])
    stub_singleton_method(Discord::ManageableGuilds, :call, result) do
      stub_singleton_method(Discord::Connections, :call, []) do
        visit "/auth/discord/callback"
        yield
      end
    end
  ensure
    OmniAuth.config.mock_auth[:discord] = nil
    OmniAuth.config.test_mode = false
  end

  test "switching the style shows the settings that style uses, and saves a choice question" do
    signed_in_as_manager do
      visit guild_team_path(@guild, @team)
      form = find("form[action='#{guild_team_questions_path(@guild, @team)}']")

      within form do
        assert_selector "input[name='application_question[placeholder]']"
        assert_no_selector "textarea[name='application_question[options_text]']"

        select "Multiple choice", from: "application_question[style]"
        assert_selector "textarea[name='application_question[options_text]']"
        assert_no_selector "input[name='application_question[placeholder]']"
        assert_selector "input[type=checkbox][name='application_question[required]']"

        select "Yes / No", from: "application_question[style]"
        assert_no_selector "textarea[name='application_question[options_text]']"
        assert_no_selector "input[type=checkbox][name='application_question[required]']"

        select "Multiple choice", from: "application_question[style]"
        fill_in "application_question[label]", with: "Main role"
        fill_in "application_question[options_text]", with: "Tank\nHealer\nDPS"
        click_on "Add"
      end

      assert_text "Question added."
      question = ActsAsTenant.without_tenant { ApplicationQuestion.find_by!(team_id: @team.id, label: "Main role") }
      assert question.choice?
      assert_equal %w[Tank Healer DPS], question.options
    end
  end
end
