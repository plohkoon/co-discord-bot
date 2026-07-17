require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin? is true only for the hardcoded admin ids" do
    assert users(:admin).admin?
    assert_not users(:member).admin?
  end
end
