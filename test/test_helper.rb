ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # Log in through the real OmniAuth callback (test mode), stubbing the Discord
  # guild fetch so no HTTP happens. Pass Guild records (or ids) to grant the
  # session Manage Server (manageable:) or plain membership (member:).
  def sign_in_as(user, manageable: [], member: [], connections: [])
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:discord] = OmniAuth::AuthHash.new(
      provider: "discord",
      uid: user.discord_id.to_s,
      info: { name: user.username },
      credentials: { token: "test-token" },
      extra: { raw_info: { "username" => user.username, "global_name" => user.global_name } }
    )
    result = Discord::ManageableGuilds::Result.new(
      Array(manageable).map { |g| { "id" => guild_id_of(g) } },
      [],
      (Array(manageable) + Array(member)).map { |g| guild_id_of(g) }
    )
    # Both remote calls the callback makes are stubbed — signing in must never
    # touch the network.
    stub_singleton_method(Discord::ManageableGuilds, :call, result) do
      stub_singleton_method(Discord::Connections, :call, Array(connections)) do
        get "/auth/discord/callback"
      end
    end
  ensure
    OmniAuth.config.mock_auth[:discord] = nil
    OmniAuth.config.test_mode = false
  end

  # Drive the Battle.net link callback for an already signed-in session.
  # `link` stands in for BattleNet::LinkAccount.call's Result.
  def link_battle_net(uid:, battletag:, link:)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:battle_net] = OmniAuth::AuthHash.new(
      provider: "battle_net",
      uid: uid.to_s,
      info: { battletag: battletag },
      credentials: { token: "bnet-test-token" },
      extra: { raw_info: { "id" => uid, "battletag" => battletag } }
    )
    stub_singleton_method(BattleNet::LinkAccount, :call, link) do
      get "/auth/battle_net/callback"
    end
  ensure
    OmniAuth.config.mock_auth[:battle_net] = nil
    OmniAuth.config.test_mode = false
  end

  def discord_connection(type:, id:, name:, verified: true)
    Discord::Connections::Connection.new(type: type, id: id, name: name, verified: verified)
  end

  private

  def guild_id_of(guild_or_id)
    (guild_or_id.respond_to?(:id) ? guild_or_id.id : guild_or_id).to_s
  end

  # Minitest 6 no longer bundles minitest/mock, so stub by redefinition.
  # A Proc value is called with the original arguments (use it to raise).
  def stub_singleton_method(mod, name, value)
    original = mod.method(name)
    mod.define_singleton_method(name) do |*args, **kwargs|
      value.is_a?(Proc) ? value.call(*args, **kwargs) : value
    end
    yield
  ensure
    mod.define_singleton_method(name, original)
  end
end
