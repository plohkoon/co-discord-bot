class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_login

  helper_method :current_user, :logged_in?, :manageable_guilds

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in? = current_user.present?

  def require_login
    return if logged_in?

    redirect_to login_path, alert: "Please sign in with Discord to continue."
  end

  # Guild ids the user can manage (co-bot installed + Manage Server), captured
  # at login. Names/details come from the Guild table.
  def manageable_guild_ids
    Array(session[:guild_ids]).map(&:to_s)
  end

  def manageable_guilds
    return Guild.none if manageable_guild_ids.empty?

    Guild.installed.where(id: manageable_guild_ids).order(:name)
  end

  # Guilds the user manages but the bot has been kicked from — the dashboard
  # offers to re-invite it there.
  def removed_guilds
    return Guild.none if manageable_guild_ids.empty?

    Guild.removed.where(id: manageable_guild_ids).order(:name)
  end

  def can_manage_guild?(guild_id)
    manageable_guild_ids.include?(guild_id.to_s)
  end
end
