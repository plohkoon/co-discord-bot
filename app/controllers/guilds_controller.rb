class GuildsController < ApplicationController
  include GuildScoping

  def show
    @teams = @guild.teams.order(:name)
  end
end
