class GuildsController < ApplicationController
  include GuildScoping
  before_action :require_guild_manager, only: %i[recheck update]

  def show
    @teams = @guild.teams.order(:name).to_a
    # This member's own upcoming call-outs — how a Discord-only raider
    # self-cancels from the web (shown to every viewer, not just managers).
    @my_absences = current_user ? Absence.active.upcoming.for_user(current_user.discord_id).order(:absence_on).to_a : []
    # One grouped query each instead of N per-team queries (tenant-scoped).
    @question_counts = ApplicationQuestion.group(:team_id).count
    @active_counts = TeamMembership.active.group(:team_id).count
    @pending_counts = TeamMembership.pending.group(:team_id).count
    # Teams the current user leads — they get to open those pages.
    @led_team_ids = current_user ? TeamOfficer.where(discord_user_id: current_user.discord_id).pluck(:team_id).to_set : Set.new
    # Permission health is a manager concern (and a REST call) — skip for members.
    @health = can_manage? ? Discord::GuildHealth.call(guild: @guild, teams: @teams) : nil
    # Curated roster lists + the log-channel pickers are manager-only (and a
    # REST call), so skip both for plain members.
    if can_manage?
      @team_categories = TeamCategory.ordered.to_a
      @team_types = TeamType.ordered.to_a
      load_channel_options
    end
  end

  # "Re-check" button on the health banner: bust the cache and re-render.
  def recheck
    Discord::GuildHealth.expire(@guild)
    redirect_to guild_path(@guild)
  end

  # Guild-level settings (Manage Server only): the log/events channels and the
  # time zone that anchors call-out days and the morning digests. Blank clears a
  # channel; a non-blank id must come from the guild's real text-channel list.
  def update
    attrs = params.require(:guild).permit(:log_channel_id, :important_log_channel_id, :events_channel_id,
                                          :time_zone, :invite_url, :slug)
    CHANNEL_SETTINGS.each { |key| attrs[key] = attrs[key].presence if attrs.key?(key) }
    # Blank clears the invite; the model rejects anything that isn't a real
    # Discord invite URL.
    attrs[:invite_url] = attrs[:invite_url].strip.presence if attrs.key?(:invite_url)
    # The public apply URL slug. Never blanked implicitly — the model's
    # presence/format/uniqueness validations answer with a friendly alert.
    attrs[:slug] = attrs[:slug].strip if attrs.key?(:slug)

    load_channel_options
    unless valid_channel_choices?(attrs)
      return redirect_to guild_path(@guild), alert: "Pick channels from the list."
    end

    if @guild.update(attrs)
      redirect_to guild_path(@guild), notice: "Server settings saved."
    else
      redirect_to guild_path(@guild), alert: @guild.errors.full_messages.to_sentence
    end
  end

  private

  # Every guild setting that holds a channel id — permitted, blank-cleared and
  # validated against the guild's real channel list as one set.
  CHANNEL_SETTINGS = %i[log_channel_id important_log_channel_id events_channel_id].freeze

  # Text-channel pickers over REST (bot token), cached briefly. Mirrors
  # TeamsController#load_discord_options (same cache key + shape). An empty
  # list (API down / bot missing) blocks setting a channel safely.
  def load_channel_options
    @channel_options = Rails.cache.fetch("discord/channel_options/#{@guild.id}", expires_in: 60.seconds) do
      Discord::BotApi.new.guild_channels(@guild.id)
                     .select { |c| c["type"].to_i.zero? } # text channels
                     .sort_by { |c| c["position"].to_i }
                     .map { |c| [ "##{c["name"]}", c["id"].to_s ] }
    end
  rescue Discord::BotApi::Error => e
    Rails.logger.warn("[web] loading channel options failed for guild #{@guild.id}: #{e.class}: #{e.message}")
    @channel_options = []
  end

  # Every submitted (non-blank) CHANNEL id must be one we fetched — rejects
  # hand-crafted PATCHes pointing logs at arbitrary channels. time_zone isn't a
  # channel, so it's validated by the model, not here.
  def valid_channel_choices?(attrs)
    valid_ids = @channel_options.map(&:last)
    attrs.slice(*CHANNEL_SETTINGS).values.compact.all? { |id| valid_ids.include?(id.to_s) }
  end
end
