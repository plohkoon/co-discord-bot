require "test_helper"

# Choice questions on the public web apply form: each style renders the input
# the Discord modal uses, posts to the same Applications::Submit, and — since
# the web path has no Discord enforcing the options — refuses answers nobody
# was offered.
class PublicApplyChoicesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @guild = Guild.create!(id: 555_000_111_222_333_444, name: "Raid Server")
    ActsAsTenant.with_tenant(@guild) do
      @team = Team.create!(name: "Alpha", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      @role = @team.application_questions.create!(position: 0, key: "role", label: "Main role",
                                                  style: :choice, options_text: "Tank\nHealer\nDPS")
      @days = @team.application_questions.create!(position: 1, key: "days", label: "Raid days",
                                                  style: :checkboxes, options_text: "Tue\nWed\nThu")
      @rules = @team.application_questions.create!(position: 2, key: "rules", label: "Read the rules?",
                                                   style: :yes_no)
    end
    sign_in_as users(:member), member: [ @guild ]
  end

  def with_membership(&block) = stub_singleton_method(Discord::GuildMembership, :call, true, &block)

  def apply(answers)
    with_membership { post public_team_applications_path(@guild.slug, @team.slug), params: { application: answers } }
  end

  def stored_answers
    ActsAsTenant.without_tenant do
      TeamApplication.order(:id).last&.application_answers&.order(:position)&.map { |a| [ a.question_label, a.answer ] }
    end
  end

  def applications_count = ActsAsTenant.without_tenant { TeamApplication.count }

  test "each style renders as the matching input" do
    with_membership { get public_team_path(@guild.slug, @team.slug) }

    assert_response :success
    assert_select "fieldset legend", text: /Main role/
    assert_select "input[type=radio][name=?]", "application[q:#{@role.id}]", count: 3
    assert_select "input[type=radio][name=?][value=?][required]", "application[q:#{@role.id}]", "Healer"
    assert_select "input[type=checkbox][name=?]", "application[q:#{@days.id}][]", count: 3
    # Yes/no: a hidden "0" so an unticked box still submits an explicit No.
    assert_select "input[type=hidden][name=?][value=?]", "application[q:#{@rules.id}]", "0"
    assert_select "input[type=checkbox][name=?][value=?]", "application[q:#{@rules.id}]", "1"
  end

  test "answers are stored as the readable options" do
    apply("q:#{@role.id}" => "Healer", "q:#{@days.id}" => %w[Thu Tue], "q:#{@rules.id}" => "1")

    assert_redirected_to public_team_path(@guild.slug, @team.slug)
    assert_equal [ [ "Main role", "Healer" ], [ "Raid days", "Tue, Thu" ], [ "Read the rules?", "Yes" ] ],
                 stored_answers
  end

  test "an unticked yes/no is recorded as No" do
    apply("q:#{@role.id}" => "Tank", "q:#{@days.id}" => %w[Wed], "q:#{@rules.id}" => "0")

    assert_equal [ "Read the rules?", "No" ], stored_answers.last
  end

  test "a crafted value that isn't an option doesn't satisfy a required choice" do
    assert_no_difference -> { applications_count } do
      apply("q:#{@role.id}" => "Sneaky", "q:#{@days.id}" => %w[Sneaky], "q:#{@rules.id}" => "1")
    end

    assert_response :unprocessable_entity
    assert_match(/Please answer: Main role, Raid days/, flash[:alert])
  end

  test "a failed submit re-renders with the choices still picked" do
    apply("q:#{@role.id}" => "Healer", "q:#{@rules.id}" => "1") # the required checkboxes left empty

    assert_response :unprocessable_entity
    assert_select "input[type=radio][value=?][checked]", "Healer"
    assert_select "input[type=checkbox][name=?][value=?][checked]", "application[q:#{@rules.id}]", "1"
  end

  test "an optional checkbox question can be left empty" do
    @days.update!(required: false)

    apply("q:#{@role.id}" => "DPS", "q:#{@rules.id}" => "0")

    assert_equal [ [ "Main role", "DPS" ], [ "Raid days", "" ], [ "Read the rules?", "No" ] ], stored_answers
  end
end
