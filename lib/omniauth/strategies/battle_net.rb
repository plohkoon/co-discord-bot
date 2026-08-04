require "omniauth-oauth2"

module OmniAuth
  module Strategies
    # Battle.net (Blizzard) OAuth2 login.
    #
    # Hand-rolled rather than using Blizzard's own `omniauth-bnet` gem: that gem
    # was last released in 2018, pins `omniauth ~> 1.0` (this app is on 2.x with
    # omniauth-rails_csrf_protection), and still points at the retired
    # `us.battle.net/oauth/*` hosts instead of the unified oauth.battle.net.
    # The real strategy is ~40 lines, so we own it.
    #
    # Endpoints come from Battle.net's OIDC discovery document at
    # https://oauth.battle.net/.well-known/openid-configuration — the host is
    # global even though the *API* hosts are per-region (see BattleNet::Client).
    class BattleNet < OmniAuth::Strategies::OAuth2
      option :name, "battle_net"

      option :client_options, {
        site: "https://oauth.battle.net",
        authorize_url: "https://oauth.battle.net/authorize",
        token_url: "https://oauth.battle.net/token",
        # Blizzard expects the client id/secret as HTTP Basic on the token call.
        auth_scheme: :basic_auth
      }

      # `wow.profile` gets us the character list, and is the only scope needed:
      # /userinfo (account id + BattleTag) answers on a plain access token.
      #
      # Deliberately NOT `openid`. Battle.net publishes an OIDC discovery
      # document, but asking for the openid scope makes this an OIDC request,
      # which a client not registered for it rejects with a 400 "Invalid grant
      # type or callback URL is not valid" — a message that points at the
      # redirect URI and wastes your afternoon. Every maintained Battle.net
      # client (Blizzard's own omniauth-bnet and passport-bnet, django-allauth)
      # requests game scopes only. Follow them.
      option :scope, "wow.profile"

      uid { raw_info["id"].presence&.to_s || raw_info["sub"].to_s }

      info do
        {
          battletag: raw_info["battletag"],
          nickname: raw_info["battletag"],
          name: raw_info["battletag"]
        }
      end

      extra { { raw_info: raw_info } }

      def raw_info
        @raw_info ||= access_token.get("/userinfo").parsed || {}
      end

      # Blizzard validates the redirect_uri exactly, so it must not carry the
      # inbound query string OmniAuth's default appends on the callback leg.
      def callback_url
        full_host + script_name + callback_path
      end
    end
  end
end

OmniAuth.config.add_camelization("battle_net", "BattleNet")
