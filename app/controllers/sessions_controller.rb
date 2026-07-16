class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create failure]

  def new
    redirect_to root_path if logged_in?
  end

  # OAuth callback
  def create
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)

    reset_session
    session[:user_id] = user.id
    session[:guilds]  = Discord::ManageableGuilds.call(token: auth.credentials.token)

    redirect_to root_path, notice: "Signed in as #{user.display_name}."
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
end
