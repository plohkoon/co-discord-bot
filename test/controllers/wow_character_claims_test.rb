require "test_helper"

# Claiming a character from the account page — the path that needs no Battle.net
# link, which is the whole reason it exists.
class WowCharacterClaimsTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 7, 27)

  def stub_claim(result)
    stub_singleton_method(WowCharacters::Claim, :call, result) { yield }
  end

  def character(user: users(:member), verified: false, **overrides)
    user.wow_characters.create!({
      blizzard_id: 42, name: "Thrall", realm: "Sargeras", realm_slug: "sargeras",
      region: "us", level: 90, claimed_at: NOW, verified_at: (NOW if verified)
    }.merge(overrides))
  end

  test "claiming a character stores it and queues a refresh" do
    sign_in_as users(:member)
    claimed = character

    assert_enqueued_with(job: WowCharacterRefreshJob) do
      stub_claim(WowCharacters::Claim::Result.new(character: claimed, status: :claimed)) do
        post wow_characters_path, params: { name: "Thrall", realm: "sargeras", region: "us" }
      end
    end

    assert_redirected_to account_path
    assert_match(/unverified/i, flash[:notice], "the notice must not imply it's proven")
  end

  test "a rejected claim reports why and queues nothing" do
    sign_in_as users(:member)

    stub_claim(WowCharacters::Claim::Result.new(character: nil, status: :failed,
                                                error: "Someone else has already claimed that character.")) do
      post wow_characters_path, params: { name: "Thrall", realm: "sargeras" }
    end

    assert_redirected_to account_path
    assert_equal "Someone else has already claimed that character.", flash[:alert]
    assert_no_enqueued_jobs only: WowCharacterRefreshJob
  end

  test "the account page lists claimed characters as unverified" do
    character
    sign_in_as users(:member)

    get account_path

    assert_response :success
    assert_match "Thrall-Sargeras", response.body
    assert_match "unverified", response.body
  end

  test "releasing a claim removes it" do
    claimed = character
    sign_in_as users(:member)

    delete wow_character_path(claimed)

    assert_redirected_to account_path
    assert_equal 0, WowCharacter.count
  end

  # A verified character belongs to the Battle.net link; unlinking that is how
  # it goes away, not a "release" button that would silently desync the two.
  test "a verified character cannot be released this way" do
    verified = character(verified: true)
    sign_in_as users(:member)

    delete wow_character_path(verified)

    assert_response :not_found
    assert_equal 1, WowCharacter.count
  end

  test "one user cannot release another's claim" do
    theirs = character(user: users(:admin))
    sign_in_as users(:member)

    delete wow_character_path(theirs)

    assert_response :not_found
    assert_equal 1, WowCharacter.count
  end

  test "claiming requires a signed-in user" do
    post wow_characters_path, params: { name: "Thrall", realm: "sargeras" }

    assert_redirected_to login_path
  end
end
