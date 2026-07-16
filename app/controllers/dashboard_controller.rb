class DashboardController < ApplicationController
  def index
    @guilds = manageable_guilds
  end
end
