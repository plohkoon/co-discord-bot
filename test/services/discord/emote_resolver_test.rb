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

  # --- resolve_text: the lenient inline form for free-typed fields ---

  def resolve_text(input, emojis: EMOJIS)
    Discord::EmoteResolver.resolve_text(guild_id: 1, input: input, api: FakeApi.new(emojis))
  end

  test "resolve_text rewrites known shortcodes inline, case-insensitively" do
    assert_equal "Raid <:swordguy:9001> night <a:partyblob:9002>!",
                 resolve_text("Raid :SwordGuy: night :partyblob:!")
  end

  test "resolve_text leaves unknown shortcodes and plain colons as typed" do
    assert_equal "Doors :nope: at 7:30:00 — Req: iLvl", resolve_text("Doors :nope: at 7:30:00 — Req: iLvl")
  end

  test "resolve_text never re-resolves an existing mention" do
    assert_equal "a <:swordguy:1234> b", resolve_text("a <:swordguy:1234> b")
  end

  test "resolve_text skips the API when there's nothing to resolve" do
    api = Object.new # would raise NoMethodError if the API were called
    assert_equal "Tuesdays 7-10pm CT", Discord::EmoteResolver.resolve_text(guild_id: 1, input: "Tuesdays 7-10pm CT", api: api)
    assert_nil Discord::EmoteResolver.resolve_text(guild_id: 1, input: nil, api: api)
  end

  test "resolve_text returns the text unchanged when the API fails" do
    failing = Object.new
    def failing.guild_emojis(_guild_id) = raise(Discord::BotApi::Error, "down")

    assert_equal "hi :swordguy:", Discord::EmoteResolver.resolve_text(guild_id: 1, input: "hi :swordguy:", api: failing)
  end
end
