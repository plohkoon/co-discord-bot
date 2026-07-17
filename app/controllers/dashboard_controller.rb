class DashboardController < ApplicationController
  def index
    @guilds = manageable_guilds
    @member_guilds = member_guilds
    @removed_guilds = removed_guilds
    @installable = installable_guilds
  end

  # Polled by the dashboard while "Add co-bot" cards are visible: reports
  # whether any of the given (still-installable) servers has joined since,
  # so the page can reload and show the new server card.
  def install_status
    ids = Array(params[:ids]).map(&:to_s) & stored_installable_ids
    render json: { ready: Guild.where(id: ids).exists? }
  end
end
