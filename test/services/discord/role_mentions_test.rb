require "test_helper"

class Discord::RoleMentionsTest < ActiveSupport::TestCase
  GUILD = 42

  ROLES = [
    { "id" => "100", "name" => "Raid Team",      "mentionable" => true },
    { "id" => "101", "name" => "Raid Team Lead", "mentionable" => true },
    { "id" => "102", "name" => "Raid",           "mentionable" => true },
    { "id" => "103", "name" => "Officers",       "mentionable" => false }, # never pinged
    { "id" => "104", "name" => "PvP (Casual)",   "mentionable" => true },  # regex-special chars
    { "id" => GUILD.to_s, "name" => "@everyone", "mentionable" => true }   # can't happen, still refused
  ].freeze

  class FakeApi
    def initialize(roles) = @roles = roles
    def guild_roles(_guild_id) = @roles
  end

  def resolve(text, roles: ROLES)
    Discord::RoleMentions.call(guild_id: GUILD, text: text, api: FakeApi.new(roles))
  end

  test "resolves a role name with spaces" do
    assert_equal [ "100" ], resolve("Come along @Raid Team, bring flasks")
  end

  test "the longest matching role wins" do
    assert_equal [ "101" ], resolve("ping @Raid Team Lead please")
    assert_equal [ "102" ], resolve("ping @Raid please")
  end

  test "a longer word starting with a role name is not a match" do
    # "Raid" is a role; "@Raiders" is not, and must not ping it.
    assert_empty resolve("@Raiders assemble")
  end

  test "matching is case-insensitive" do
    assert_equal [ "100" ], resolve("@raid team tonight")
  end

  test "role names containing regex characters are matched literally" do
    assert_equal [ "104" ], resolve("@PvP (Casual) sign up")
  end

  test "non-mentionable roles are skipped" do
    assert_empty resolve("@Officers heads up")
  end

  test "everyone and here can never be resolved" do
    assert_empty resolve("@everyone @here get in here")
  end

  test "an at-sign inside a word is not a mention" do
    assert_empty resolve("mail someone@Raid.example.com")
  end

  test "a pasted role mention is honored when the role is mentionable" do
    assert_equal [ "100" ], resolve("<@&100> tonight")
  end

  test "a pasted mention for a non-mentionable role is skipped" do
    assert_empty resolve("<@&103> tonight")
  end

  test "multiple roles keep first-appearance order and dedupe" do
    assert_equal [ "102", "100" ], resolve("@Raid and @Raid Team and @Raid again")
  end

  test "blank and unmatched text resolve to nothing" do
    assert_empty resolve(nil)
    assert_empty resolve("")
    assert_empty resolve("no pings here at all")
    assert_empty resolve("@Nobody in particular")
  end

  test "a guild with no mentionable roles resolves to nothing" do
    assert_empty resolve("@Officers", roles: [ ROLES[3] ])
  end

  test "an API failure degrades to no pings rather than blocking the post" do
    api = Object.new
    api.define_singleton_method(:guild_roles) { |_id| raise Discord::BotApi::Error, "boom" }

    assert_empty Discord::RoleMentions.call(guild_id: GUILD, text: "@Raid Team", api: api)
  end
end
