class AccountController < ApplicationController
  # Per-person settings, deliberately outside GuildScoping: a Battle.net link
  # belongs to the human, not to any one server.
  def show
    @battle_net_accounts = current_user.battle_net_accounts
                                       .includes(:wow_characters)
                                       .recently_linked_first
    @battle_net_configured = BattleNet::Client.configured?
    # Characters the user claimed without proving ownership. Listed apart from
    # the linked ones so the difference is visible rather than implied.
    @claimed_characters = current_user.wow_characters.unverified.by_prominence
    @regions = BattleNet::Client::REGIONS
  end
end
