require "test_helper"

module Admin
  class AdminPanelTest < ActionDispatch::IntegrationTest
    test "anonymous visitors are sent to login" do
      get admin_root_path
      assert_redirected_to login_path
    end

    test "non-admin users are blocked" do
      sign_in_as users(:member)

      get admin_root_path
      assert_redirected_to root_path

      get admin_jobs_path
      assert_redirected_to root_path

      get admin_resources_path("users")
      assert_redirected_to root_path
    end

    test "admin sees the dashboard" do
      sign_in_as users(:admin)

      get admin_root_path
      assert_response :success
      assert_select "h1", text: "Admin panel"
    end

    test "admin can browse a model index, search it, and open a record" do
      sign_in_as users(:admin)

      get admin_resources_path("users")
      assert_response :success
      assert_select "td", text: /greg/

      get admin_resources_path("users", q: "pleb")
      assert_response :success
      assert_select "td", text: /pleb/
      assert_select "td", text: /greg/, count: 0

      get admin_resource_path("users", users(:admin).id)
      assert_response :success
    end

    test "every model's index renders, and show handles associations and snowflake PKs" do
      sign_in_as users(:admin)

      guild = Guild.create!(id: 99_999_999_999_999_999, name: "Test Server")
      ActsAsTenant.with_tenant(guild) do
        Team.create!(name: "Raiders", team_role_id: 1, officer_role_id: 2, review_channel_id: 3)
      end

      Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models").to_s)
      keys = ApplicationRecord.descendants.reject(&:abstract_class?).map { |k| k.model_name.plural }
      assert_includes keys, "teams"

      keys.each do |key|
        get admin_resources_path(key)
        assert_response :success, "index for #{key.inspect} failed"
      end

      get admin_resource_path("guilds", guild.id)
      assert_response :success
      assert_select "a", text: /Teams/
    end

    test "unknown model 404s" do
      sign_in_as users(:admin)

      get admin_resources_path("bogus")
      assert_response :not_found
    end

    test "admin can view every jobs tab" do
      sign_in_as users(:admin)

      Admin::JobsController::TABS.each do |tab|
        get admin_jobs_path(tab: tab)
        assert_response :success, "jobs tab #{tab.inspect} failed"
      end
    end
  end
end
