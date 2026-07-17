require "test_helper"

class EmoteResolverTest < ActiveSupport::TestCase
  class FakeApi
    def initialize(emojis) = @emojis = emojis
    def guild_emojis(_guild_id) = @emojis
  end

  EMOJIS = [
    { "id" => "9001", "name" => "swordguy", "animated" => false },
    { "id" => "9002", "name" => "partyblob", "animated" => true }
  ].freeze

  def resolve(input, emojis: EMOJIS)
    Discord::EmoteResolver.call(guild_id: 1, input: input, api: FakeApi.new(emojis))
  end

  test "unicode and blank pass through without hitting the API" do
    api = Object.new # would raise NoMethodError if the API were called
    assert_equal "⚔️", Discord::EmoteResolver.call(guild_id: 1, input: " ⚔️ ", api: api)
    assert_nil Discord::EmoteResolver.call(guild_id: 1, input: "   ", api: api)
    assert_nil Discord::EmoteResolver.call(guild_id: 1, input: nil, api: api)
  end

  test "full mention forms pass through verbatim" do
    api = Object.new
    assert_equal "<:swordguy:9001>", Discord::EmoteResolver.call(guild_id: 1, input: "<:swordguy:9001>", api: api)
    assert_equal "<a:partyblob:9002>", Discord::EmoteResolver.call(guild_id: 1, input: "<a:partyblob:9002>", api: api)
  end

  test "a shortcode resolves case-insensitively to the mention form" do
    assert_equal "<:swordguy:9001>", resolve(":swordguy:")
    assert_equal "<:swordguy:9001>", resolve(":SwordGuy:")
  end

  test "an animated emote resolves to the <a:...> form" do
    assert_equal "<a:partyblob:9002>", resolve(":partyblob:")
  end

  test "an unknown shortcode raises UnknownEmote with the name" do
    error = assert_raises(Discord::EmoteResolver::UnknownEmote) { resolve(":nope:") }
    assert_equal "nope", error.name
  end
end
