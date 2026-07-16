# For dashboard controllers scoped to one guild. Authorizes that the current
# user manages the guild, then runs the action inside the guild tenant so every
# query is auto-scoped (acts_as_tenant).
module GuildScoping
  extend ActiveSupport::Concern

  included do
    before_action :set_guild
    around_action :scope_to_guild
  end

  private

  def set_guild
    id = params[:guild_id] || params[:id]

    unless can_manage_guild?(id)
      redirect_to(root_path, alert: "You don't manage that server.")
      return
    end

    @guild = Guild.find_by(id: id)
    if @guild.nil?
      redirect_to(root_path, alert: "That server isn't set up yet.")
    elsif @guild.removed?
      @guild = nil
      redirect_to(root_path, alert: "co-bot was removed from that server. Re-invite it to manage it again.")
    end
  end

  def scope_to_guild(&block)
    return unless @guild # a redirect already happened in set_guild

    ActsAsTenant.with_tenant(@guild, &block)
  end
end
