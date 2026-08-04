require "test_helper"

class WowCharacterTest < ActiveSupport::TestCase
  def account
    @account ||= users(:member).battle_net_accounts.create!(
      battle_net_id: 1, battle_tag: "Thrall#1234", region: "us", linked_at: Time.current
    )
  end

  def character(name:, realm: "Sargeras", slug: "sargeras")
    account.wow_characters.create!(blizzard_id: name.hash.abs, name: name, realm: realm,
                                   realm_slug: slug, level: 80, verified_at: Time.current)
  end

  test "full_name is the form players actually use" do
    assert_equal "Thrall-Illidan", character(name: "Thrall", realm: "Illidan", slug: "illidan").full_name
  end

  # Accented names are ordinary in WoW. A raw interpolation survives an href but
  # breaks the moment the URL is handed to an HTTP client (Raider.io, Armory).
  test "accented names are percent-encoded in outbound URLs" do
    accented = character(name: "Jörmûngandr")

    assert_equal "https://raider.io/characters/us/sargeras/J%C3%B6rm%C3%BBngandr", accented.raider_io_url
    assert_equal "https://worldofwarcraft.blizzard.com/en-us/character/us/sargeras/j%C3%B6rm%C3%BBngandr",
                 accented.armory_url
    assert_no_match(/[^\x00-\x7F]/, accented.raider_io_url, "URL must be pure ASCII")
    assert_no_match(/[^\x00-\x7F]/, accented.armory_url, "URL must be pure ASCII")
  end

  test "plain names are unchanged apart from Blizzard's lowercasing" do
    plain = character(name: "Morhigahn")

    assert_equal "https://raider.io/characters/us/sargeras/Morhigahn", plain.raider_io_url
    assert_equal "https://worldofwarcraft.blizzard.com/en-us/character/us/sargeras/morhigahn", plain.armory_url
  end

  test "region is delegated from the linked account" do
    assert_equal "us", character(name: "Thrall").region
  end

  test "by_prominence puts the characters a lead cares about first" do
    account.wow_characters.create!(blizzard_id: 1, name: "Alt", realm: "Sargeras",
                                   realm_slug: "sargeras", level: 12, verified_at: Time.current)
    account.wow_characters.create!(blizzard_id: 2, name: "Main", realm: "Sargeras",
                                   realm_slug: "sargeras", level: 90, verified_at: Time.current)

    assert_equal %w[Main Alt], account.wow_characters.by_prominence.pluck(:name)
  end
end
