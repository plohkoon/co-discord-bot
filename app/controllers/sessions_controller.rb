class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create failure]

  def new
    @return_to = requested_return_path
    redirect_to @return_to || root_path if logged_in?
  end

  # OAuth callback
  def create
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)

    guilds = Discord::ManageableGuilds.call(token: auth.credentials.token)

    reset_session
    session[:user_id] = user.id
    # Store only ids (names come from the Guild table) to keep the session cookie
    # well under CookieStore's 4KB limit — the full array can overflow it.
    session[:guild_ids] = guilds.manageable.map { |g| g["id"] }
    # Known guilds the user merely belongs to — view access. Small: only ids,
    # only guilds with a Guild row.
    session[:member_guild_ids] = guilds.member
    # Installable servers (no Guild row) keep their names on the user row instead.
    user.update!(installable_guilds: guilds.installable)
    # Third-party accounts the user has already linked on Discord's side. Best
    # effort — Discord::Connections swallows its own errors, and a user who
    # authorized before we asked for the `connections` scope simply gets none
    # until their next sign-in.
    user.record_discord_connections!(Discord::Connections.call(token: auth.credentials.token))

    redirect_to after_sign_in_path, notice: "Signed in as #{user.display_name}."
  rescue => e
    Rails.logger.error("[web] sign-in failed: #{e.class}: #{e.message}")
    redirect_to login_path, alert: "Sign-in failed. Please try again."
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end

  def failure
    redirect_to login_path, alert: "Discord sign-in was cancelled or failed."
  end

  private

  # Return-to after login, via OmniAuth's origin mechanism: the login form's
  # `origin` param lands in request.env["omniauth.origin"] on the callback.
  # Validated down to a relative same-app path — never a full URL — so a
  # crafted link can't turn the login flow into an open redirect.
  def after_sign_in_path
    safe_internal_path(request.env["omniauth.origin"]) || root_path
  end

  # The ?return_to the login page arrived with (from require_login), if safe to
  # honor. Feeds the login form's hidden `origin` field.
  def requested_return_path
    safe_internal_path(params[:return_to])
  end

  # Accept only relative same-app paths: must start with "/", and not "//" or
  # "/\" (both of which browsers treat as protocol-relative URLs to another
  # host).
  def safe_internal_path(value)
    path = value.to_s
    path if path.start_with?("/") && !path.start_with?("//", "/\\")
  end
end
