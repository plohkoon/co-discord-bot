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

  # Guild ids the user can manage: captured at login, plus servers from the
  # installable list whose Guild row has since appeared (the "Add co-bot" flow —
  # Manage Server was verified at login, the same trust as session[:guild_ids],
  # so no re-login is needed after an install).
  def manageable_guild_ids
    Array(session[:guild_ids]).map(&:to_s) | promoted_guild_ids
  end

  def stored_installable_guilds
    Array(current_user&.installable_guilds)
  end

  def stored_installable_ids
    stored_installable_guilds.map { |g| g["id"].to_s }
  end

  def promoted_guild_ids
    return [] if stored_installable_ids.empty?

    Guild.where(id: stored_installable_ids).pluck(:id).map(&:to_s)
  end

  # Installable servers still without a Guild row — the dashboard's "Add co-bot"
  # cards. Names come from the user row (there's no Guild row to read them from).
  def installable_guilds
    promoted = promoted_guild_ids.to_set
    stored_installable_guilds.reject { |g| promoted.include?(g["id"].to_s) }
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

  # --- View access (membership, not management) ---
  # Anyone in a server can view it on the web; managing it (or a team in it)
  # takes Manage Server or a team-lead role. Membership ids are captured at
  # login; team leads are additionally recognized via the team_officers mirror
  # so they keep access even if their session predates the officer role.

  def officer_guild_ids
    return [] unless current_user

    TeamOfficer.where(discord_user_id: current_user.discord_id)
               .distinct.pluck(:guild_id).map(&:to_s)
  end

  def viewable_guild_ids
    manageable_guild_ids | Array(session[:member_guild_ids]).map(&:to_s) | officer_guild_ids
  end

  def can_view_guild?(guild_id)
    viewable_guild_ids.include?(guild_id.to_s)
  end

  # Servers the user can view but not manage — the dashboard's second list.
  def member_guilds
    ids = viewable_guild_ids - manageable_guild_ids
    return Guild.none if ids.empty?

    Guild.installed.where(id: ids).order(:name)
  end
end
