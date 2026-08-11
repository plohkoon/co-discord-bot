require "test_helper"

# The web role pickers must never offer a role carrying a dangerous Discord
# permission — a Manage-Server user could otherwise make the bot grant
# Administrator. Discord serialises `permissions` as a decimal STRING.
class Discord::PermissionsTest < ActiveSupport::TestCase
  def role(permissions) = { "permissions" => permissions }

  test "a role with no permissions field is safe" do
    assert_not Discord::Permissions.dangerous_role?({ "name" => "Raider" })
  end

  test "nil, blank, and zero all read as safe" do
    assert_not Discord::Permissions.dangerous_role?(role(nil))
    assert_not Discord::Permissions.dangerous_role?(role(""))
    assert_not Discord::Permissions.dangerous_role?(role("0"))
  end

  test "a harmless permission (e.g. Send Messages, 0x800) is safe" do
    assert_not Discord::Permissions.dangerous_role?(role("2048"))
  end

  test "each dangerous bit is caught on its own" do
    {
      "Administrator"   => "8",         # 1 << 3
      "Kick"            => "2",         # 1 << 1
      "Ban"             => "4",         # 1 << 2
      "Manage Channels" => "16",        # 1 << 4
      "Manage Guild"    => "32",        # 1 << 5
      "Manage Roles"    => "268435456"  # 1 << 28
    }.each do |label, bits|
      assert Discord::Permissions.dangerous_role?(role(bits)), "#{label} (#{bits}) should be dangerous"
    end
  end

  test "a dangerous bit mixed into an otherwise harmless bitfield is caught" do
    # Send Messages (0x800) + Administrator (0x8) = 2056
    assert Discord::Permissions.dangerous_role?(role("2056"))
  end

  test "a large real-world bitfield string is parsed, not overflowed" do
    # A role with many permissions but none dangerous: View Channel (0x400) +
    # Send Messages (0x800) + Add Reactions (0x40) = 3136.
    assert_not Discord::Permissions.dangerous_role?(role("3136"))
  end

  test "an unparseable permissions value fails closed (treated as dangerous)" do
    assert Discord::Permissions.dangerous_role?(role("not-a-number"))
  end
end
