# Manage Server CRUD for WoW role-reward rules (guild page section). Creating
# a rule kicks off an immediate evaluation so the admin sees it work; deleting
# one only stops future grants — roles already granted stay on people.
class RoleRewardsController < ApplicationController
  include GuildScoping
  before_action :require_guild_manager

  def create
    reward = RoleReward.new(reward_params)

    # The role must come from the guild's fetched role list (same rule as the
    # team form) — rejects hand-crafted POSTs pointing the bot at arbitrary
    # role ids, and managed/@everyone roles are never in the list.
    unless role_options.map(&:last).include?(reward.discord_role_id.to_s)
      return redirect_to guild_path(@guild), alert: "Pick the role to grant from the list."
    end

    if reward.save
      RoleRewardSweepJob.perform_later(guild_id: @guild.id)
      redirect_to guild_path(@guild), notice: "Role reward added. Qualifying members are being checked now."
    else
      redirect_to guild_path(@guild), alert: reward.errors.full_messages.to_sentence
    end
  end

  def destroy
    RoleReward.find(params[:id]).destroy
    redirect_to guild_path(@guild), notice: "Role reward removed. Roles already granted were kept."
  end

  private

  def reward_params
    params.require(:role_reward).permit(:kind, :discord_role_id, :achievement_name,
                                        :threshold, :pvp_bracket_type, :auto_revoke)
  end

  # Mirrors TeamsController#load_discord_options' role half (same cache key +
  # shape). An empty list (API down / bot missing / no token) blocks creation
  # safely.
  def role_options
    Rails.cache.fetch("discord/role_options/#{@guild.id}", expires_in: 60.seconds) do
      Discord::BotApi.new.guild_roles(@guild.id)
                     .reject { |r| r["managed"] || r["id"].to_s == @guild.id.to_s } # bot-managed roles + @everyone
                     .reject { |r| Discord::Permissions.dangerous_role?(r) } # never auto-grant Admin/Manage/Ban/Kick roles
                     .sort_by { |r| -r["position"].to_i }
                     .map { |r| [ r["name"], r["id"].to_s ] }
    end
  rescue Discord::BotApi::Error => e
    Rails.logger.warn("[web] loading role options failed for guild #{@guild.id}: #{e.class}: #{e.message}")
    []
  end
end
