class BattleNetAccountsController < ApplicationController
  # The OAuth callback lands on a session that's already signed in — linking is
  # not a login, so require_login still applies (and `failure` needs it too, so
  # a cancelled link returns somewhere useful).

  # Battle.net OAuth callback.
  def create
    auth = request.env["omniauth.auth"]
    return redirect_to(account_path, alert: "Battle.net didn't complete the link.") if auth.blank?

    result = BattleNet::LinkAccount.call(user: current_user, auth: auth)

    if result.ok?
      redirect_to account_path, notice: link_notice(result)
    else
      redirect_to account_path, alert: result.error
    end
  end

  # Re-pull live character data. Runs on the app token, so this works whether or
  # not the user's original OAuth grant is still alive.
  def refresh
    account = current_user.battle_net_accounts.find(params[:id])
    ids = account.wow_characters
                 .refreshable(min_level: WowCharacterSweepJob::MIN_LEVEL)
                 .by_prominence.pluck(:id)
    ids.each { |id| WowCharacterRefreshJob.perform_later(id) }

    redirect_to account_path,
                notice: "Refreshing #{helpers.pluralize(ids.size, "character")} from Blizzard — check back in a moment."
  end

  def destroy
    account = current_user.battle_net_accounts.find(params[:id])
    account.destroy!
    redirect_to account_path, notice: "Unlinked #{account.display_name}."
  end

  def failure
    redirect_to account_path, alert: "Battle.net linking was cancelled or failed."
  end

  private

  def link_notice(result)
    count = result.characters.size
    name = result.account.display_name
    return "Linked #{name}, but Blizzard didn't return any characters." if count.zero?

    "Linked #{name} — #{helpers.pluralize(count, "character")} verified."
  end
end
