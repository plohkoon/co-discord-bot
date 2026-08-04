require "test_helper"

module WowCharacters
  class SetMainTest < ActiveSupport::TestCase
    NOW = Time.utc(2026, 7, 27)

    def user = users(:member)

    def character(name, level: 90, last_login: nil, owner: user, missing: false)
      owner.wow_characters.create!(
        blizzard_id: name.hash.abs, name: name, realm: "Sargeras", realm_slug: "sargeras",
        region: "us", level: level, last_login_at: last_login,
        missing_at: (NOW if missing), claimed_at: NOW
      )
    end

    # With one character there is no other sensible answer.
    test "the first character someone gets becomes their main" do
      thrall = character("Thrall")

      assert_equal thrall, SetMain.ensure(user)
      assert_equal thrall, user.reload.main_wow_character
    end

    # Fifty arrive at once from a Battle.net link and none is flagged, so this
    # is a guess — but a defensible one.
    test "level is the strong signal" do
      character("Alt", level: 40)
      main = character("Main", level: 90)

      assert_equal main, SetMain.ensure(user)
    end

    test "recency breaks ties between max-level characters" do
      character("Stale", level: 90, last_login: NOW - 200.days)
      recent = character("Recent", level: 90, last_login: NOW - 1.day)

      assert_equal recent, SetMain.ensure(user)
    end

    # last_login_at is nil until a refresh has run; it must not beat a character
    # we know was played yesterday.
    test "an unrefreshed character does not outrank one known to be active" do
      character("Unknown", level: 90, last_login: nil)
      played = character("Played", level: 90, last_login: NOW - 1.day)

      assert_equal played, SetMain.ensure(user)
    end

    test "characters Blizzard has lost are never chosen" do
      character("Gone", level: 90, missing: true)
      alive = character("Alive", level: 80)

      assert_equal alive, SetMain.ensure(user)
    end

    # --- Authority ---

    test "an explicit choice is never overridden by inference" do
      alt = character("Alt", level: 40)
      character("Higher", level: 90)
      SetMain.set(user, alt)

      assert_equal alt, SetMain.ensure(user), "ensure fills a gap; it does not second-guess"
      assert_equal alt, user.reload.main_wow_character
    end

    test "a character someone does not own cannot be set as their main" do
      theirs = character("Theirs", owner: users(:admin))

      assert_not SetMain.set(user, theirs)
      assert_nil user.reload.main_wow_character
    end

    # A released, unlinked or transferred main leaves a dangling pointer.
    test "a main that has gone missing is quietly replaced" do
      gone = character("Gone", level: 90)
      SetMain.set(user, gone)
      replacement = character("Replacement", level: 85)
      gone.update!(missing_at: NOW)

      assert_equal replacement, SetMain.ensure(user.reload)
    end

    test "a main deleted outright clears the pointer and picks again" do
      gone = character("Gone", level: 90)
      SetMain.set(user, gone)
      replacement = character("Replacement", level: 85)
      gone.destroy!

      assert_equal replacement, SetMain.ensure(user.reload)
    end

    test "someone with no characters has no main and no error" do
      assert_nil SetMain.ensure(user)
      assert_nil user.reload.main_wow_character
    end

    test "User#main_character fills a gap rather than returning nil" do
      thrall = character("Thrall")

      assert_equal thrall, user.main_character
    end
  end
end
