# Base for the shareable /apply pages. Deliberately NOT GuildScoping — that
# concern bounces anyone who isn't already a known member to the dashboard,
# which is exactly wrong for a page whose audience is prospective members.
#
# These pages are genuinely public: anonymous visitors can VIEW everything
# (guild blurb, team cards, recruiting state) with a "Sign in with Discord to
# apply" banner in place of the forms — no account needed to window-shop.
# Signing in (with return-to, so the pasted link survives the OAuth round
# trip) is required only to actually submit an application, and the POST
# re-asserts that server-side. The guild is found without any access check
# (removed/unknown guilds 404), actions run inside the guild tenant, and each
# controller checks live Discord membership itself. Membership is NOT a gate:
# outsiders are the intended recruiting audience, so non-members see the teams
# and can apply too — they just get a prominent "join the server" banner
# (their team role is granted by MemberJoinReconcileJob when they arrive).
class PublicBaseController < ApplicationController
  skip_before_action :require_login
  before_action :set_guild
  around_action :scope_to_guild

  helper_method :guild_member?

  private

  # Slug lookup only — raw ids 404 (the links have never shipped with ids, so
  # there's no legacy to honor).
  def set_guild
    @guild = Guild.installed.find_by(slug: params[:guild_slug])
    render "public_guilds/not_installed", status: :not_found if @guild.nil?
  end

  def scope_to_guild(&block)
    return unless @guild # the 404 already rendered in set_guild

    ActsAsTenant.with_tenant(@guild, &block)
  end

  # Live REST check (so "join, then reload" works without a re-login), falling
  # back to the membership snapshot captured at sign-in when Discord can't be
  # asked. Memoized per request — it decides the join banner and the wording of
  # the post-submit confirmation, never whether someone may apply. Anonymous
  # visitors are trivially not members (and get the sign-in banner instead of
  # the join banner) — never ask Discord about a user who isn't there.
  def guild_member?
    return false unless logged_in?
    return @guild_member if defined?(@guild_member)

    @guild_member = Discord::GuildMembership.call(
      guild_id: @guild.id,
      user_id: current_user.discord_id,
      fallback: -> { can_view_guild?(@guild.id) }
    )
  end
end
