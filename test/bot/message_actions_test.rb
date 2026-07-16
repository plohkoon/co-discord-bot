require "test_helper"

class MessageActionsTest < ActiveSupport::TestCase
  # Minimal stand-ins for the discordrb message/event the action receives.
  class FakeMessage
    attr_reader :reactions

    def initialize = @reactions = []
    def react(emoji) = @reactions << emoji
  end

  FakeEvent = Struct.new(:message)

  test "word matcher is case-insensitive and word-bounded" do
    assert MessageActions::MeatReact.matches?("I love MEAT so much")
    assert MessageActions::MeatReact.matches?("meat.")
    assert_not MessageActions::MeatReact.matches?("meatball sub")
    assert_not MessageActions::MeatReact.matches?("nothing relevant")
    assert_not MessageActions::MeatReact.matches?(nil)
  end

  test "meat react adds the steak emoji" do
    event = FakeEvent.new(FakeMessage.new)
    guild = Guild.sync_from_discord(id: 1, name: "Test")

    MessageActions::MeatReact.new(event: event, guild: guild).perform

    assert_equal [ "🥩" ], event.message.reactions
  end

  test "manifest resolves action classes and matching filters by content" do
    assert_includes CoBot::MessageActionRegistry.actions, MessageActions::MeatReact
    assert_includes CoBot::MessageActionRegistry.matching("give me meat"), MessageActions::MeatReact
    assert_empty CoBot::MessageActionRegistry.matching("give me vegetables")
  end

  test "match requires exactly one matcher kind" do
    assert_raises(ArgumentError) { Class.new(MessageActions::Base) { match word: "a", contains: "b" } }
    assert_raises(ArgumentError) { Class.new(MessageActions::Base) { match } }
  end

  test "contains and pattern matchers work" do
    contains = Class.new(MessageActions::Base) { match contains: "meat" }
    assert contains.matches?("meatball sub")

    pattern = Class.new(MessageActions::Base) { match pattern: /\Ameat/ }
    assert pattern.matches?("meat first")
    assert_not pattern.matches?("first meat")
  end

  test "unknown manifest action raises with the expected class name" do
    error = assert_raises(RuntimeError) do
      CoBot::MessageActionRegistry::Builder.new([]).action(:no_such_action)
    end
    assert_match "MessageActions::NoSuchAction", error.message
  end
end
