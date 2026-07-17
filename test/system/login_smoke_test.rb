require "application_system_test_case"

# Smoke test: the app boots, serves the login page with compiled assets, and
# gates the dashboard behind sign-in. Also keeps `bin/rails test:system` (and
# the CI system-test job) from erroring on an empty test/system directory.
class LoginSmokeTest < ApplicationSystemTestCase
  test "visiting the dashboard while signed out lands on the Discord login" do
    visit root_url

    assert_current_path login_path
    assert_selector "h1", text: "co-bot"
    assert_button "Sign in with Discord"
  end
end
