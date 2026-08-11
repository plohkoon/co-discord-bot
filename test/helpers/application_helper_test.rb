require "test_helper"

# discord_emotes renders free-typed text (bios, roster lines, guild
# descriptions) with inline custom-emote mentions swapped for Discord CDN
# images. Everything around the mentions is user input and must stay escaped.
class ApplicationHelperTest < ActionView::TestCase
  test "plain text passes through unchanged" do
    assert_equal "We push keys and clear heroic weekly.",
                 discord_emotes("We push keys and clear heroic weekly.")
  end

  test "user-typed HTML is escaped" do
    rendered = discord_emotes("<script>alert(1)</script> hi")

    assert rendered.html_safe?
    assert_includes rendered, "&lt;script&gt;alert(1)&lt;/script&gt; hi"
    assert_not_includes rendered, "<script>"
  end

  test "a static emote mention becomes a png img with alt and title" do
    rendered = discord_emotes("Bring your <:pog:123456789012345678> energy")

    assert rendered.html_safe?
    assert_includes rendered, 'src="https://cdn.discordapp.com/emojis/123456789012345678.png?size=32"'
    assert_includes rendered, 'alt=":pog:"'
    assert_includes rendered, 'title=":pog:"'
    assert_includes rendered, "Bring your "
    assert_not_includes rendered, "&lt;:pog:"
  end

  test "an animated emote mention becomes a gif img" do
    rendered = discord_emotes("<a:party:987654321098765432> woo")

    assert_includes rendered, 'src="https://cdn.discordapp.com/emojis/987654321098765432.gif?size=32"'
    assert_includes rendered, 'alt=":party:"'
  end

  test "multiple emotes in one string all render" do
    rendered = discord_emotes("<:tank:111> and <a:heal:222> needed")

    assert_includes rendered, "emojis/111.png"
    assert_includes rendered, "emojis/222.gif"
    assert_equal 2, rendered.scan("<img").size
    assert_includes rendered, " and "
    assert_includes rendered, " needed"
  end

  test "literal colons in free text are left alone" do
    text = "Raid at 7:30:00 — Req: iLvl 250+ :unknown:"

    assert_equal "Raid at 7:30:00 — Req: iLvl 250+ :unknown:", discord_emotes(text)
  end

  test "nil and blank echo through" do
    assert_nil discord_emotes(nil)
    assert_equal "", discord_emotes("")
  end
end
