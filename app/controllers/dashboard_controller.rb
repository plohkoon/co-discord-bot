class DashboardController < ApplicationController
  def index
    @guilds = manageable_guilds
    @removed_guilds = removed_guilds
  end
end
