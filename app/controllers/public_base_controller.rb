# Base for the shareable /apply pages. Deliberately NOT GuildScoping — that
# concern bounces anyone who isn't already a known member to the dashboard,
# which is exactly wrong for a page whose audience is prospective members.
#
# Instead: sign-in is still required (with return-to, so the pasted link
# survives the OAuth round trip), the guild is found without any access check
# (removed/unknown guilds 404), actions run inside the guild tenant, and each
# controller branches on live Discord membership itself — members see teams and
# forms, non-members a join card.
class PublicBaseController < ApplicationController
  before_action :set_guild
  around_action :scope_to_guild

  helper_method :guild_member?

  private

  def set_guild
    @guild = Guild.installed.find_by(id: params[:guild_id])
    render "public_guilds/not_installed", status: :not_found if @guild.nil?
  end

  def scope_to_guild(&block)
    return unless @guild # the 404 already rendered in set_guild

    ActsAsTenant.with_tenant(@guild, &block)
  end

  # Live REST check (so "join, then reload" works without a re-login), falling
  # back to the membership snapshot captured at sign-in when Discord can't be
  # asked. Memoized per request — the guild page and its POST both branch on it.
  def guild_member?
    return @guild_member if defined?(@guild_member)

    @guild_member = Discord::GuildMembership.call(
      guild_id: @guild.id,
      user_id: current_user.discord_id,
      fallback: -> { can_view_guild?(@guild.id) }
    )
  end

  # Membership is enforced server-side on writes, not just hidden in the view.
  def require_guild_membership
    return if guild_member?

    redirect_to public_guild_path(@guild.id), alert: "Join the Discord server first — applications are for members."
  end
end
