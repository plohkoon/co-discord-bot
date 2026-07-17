class TeamsController < ApplicationController
  include GuildScoping
  # Creating teams is admin work; show and update are open to the team's leads
  # too (update mirrors the bot's officer-level /team edit — but position is
  # stripped for non-managers there).
  before_action :require_guild_manager, except: %i[show update]

  def new
    @team = @guild.teams.new
    load_discord_options
    load_roster_options
  end

  def create
    attrs = params.require(:team).permit(:name, :team_role_id, :officer_role_id, :review_channel_id,
                                         :position, :team_category_id, :team_type_id, *Team::ROSTER_FIELDS)
    resolve_text_fields(attrs)
    @team = @guild.teams.new(attrs.except(:team_category_id, :team_type_id))
    assign_roster_choices(attrs)

    load_discord_options
    load_roster_options
    unless valid_discord_choices?
      flash.now[:alert] = "Pick the team role, officer role, and review channel from the lists."
      return render :new, status: :unprocessable_entity
    end

    emote, emote_error = resolve_emote(@team.emote)
    if emote_error
      flash.now[:alert] = emote_error
      return render :new, status: :unprocessable_entity
    end
    @team.emote = emote

    if @team.save
      @team.seed_default_questions!
      # Same sweep as /team create: existing role holders become members and
      # the officers mirror is seeded (no interaction token — no follow-up).
      TeamBackfillJob.perform_later(guild_id: @guild.id, team_id: @team.id)
      redirect_to guild_team_path(@guild, @team),
                  notice: "Team created. Existing role holders are being picked up in the background."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @team = @guild.teams.find(params[:id])
    require_team_access
    return if performed?

    load_roster_options if can_manage? || officer_of?(@team)
    @questions = @team.application_questions.ordered
    @new_question = @team.application_questions.build(required: true)

    memberships = @team.team_memberships.order(updated_at: :desc).to_a
    @members_by_status = memberships.group_by(&:status)
    @counts = %w[active pending archived].index_with { |status| @members_by_status[status]&.size || 0 }
    @app_counts = TeamApplication.where(team_membership_id: memberships.map(&:id)).group(:team_membership_id).count
  end

  # Name + roster details (category, type + the free-form lines shown by
  # /team roster). Open to the team's leads, except position — directory
  # placement relative to OTHER teams is a server-layout call, so it's
  # Manage Server only (the form hides the field; this also stops hand-
  # crafted PATCHes).
  def update
    @team = @guild.teams.find(params[:id])
    require_team_access
    return if performed?

    attrs = params.require(:team).permit(:name, :position, :team_category_id, :team_type_id, *Team::ROSTER_FIELDS)
    attrs.delete(:position) unless can_manage?
    resolve_text_fields(attrs)

    @team.assign_attributes(attrs.except(:team_category_id, :team_type_id))
    assign_roster_choices(attrs)

    emote, emote_error = resolve_emote(@team.emote)
    return redirect_to guild_team_path(@guild, @team), alert: emote_error if emote_error

    @team.emote = emote

    if @team.save
      RosterRefreshJob.perform_later(guild_id: @guild.id)
      redirect_to guild_team_path(@guild, @team), notice: "Team updated."
    else
      redirect_to guild_team_path(@guild, @team), alert: @team.errors.full_messages.to_sentence
    end
  end

  private

  # Category and type come from the guild's curated lists. Lookups are
  # tenant-scoped, so ids from another guild (or a blank select) resolve to
  # nil and clear the association.
  def assign_roster_choices(attrs)
    @team.team_category = TeamCategory.find_by(id: attrs[:team_category_id])
    @team.team_type = TeamType.find_by(id: attrs[:team_type_id])
  end

  # Select options for the roster form.
  def load_roster_options
    @team_categories = TeamCategory.ordered.to_a
    @team_types = TeamType.ordered.to_a
  end

  # Inline emote resolution for the free-typed fields: known :name: shortcodes
  # become mentions so they render in the roster; unknown ones stay as typed.
  # The standalone emote field is stricter — see resolve_emote below.
  def resolve_text_fields(attrs)
    ([ :name ] + (Team::ROSTER_FIELDS - [ :emote ])).each do |field|
      attrs[field] = Discord::EmoteResolver.resolve_text(guild_id: @guild.id, input: attrs[field]) if attrs[field]
    end
  end

  # [resolved, error_message] — :name: is expanded against the guild's emoji
  # list (bots must post the full <:name:id> form; the shorthand only renders
  # when a human types it); unicode and full mentions pass through. Unlike the
  # inline fields, this standalone field MUST resolve — a broken heading emote
  # is worse than an error.
  def resolve_emote(raw)
    [ Discord::EmoteResolver.call(guild_id: @guild.id, input: raw), nil ]
  rescue Discord::EmoteResolver::UnknownEmote => e
    [ nil, "This server has no emote named :#{e.name}: — check the name, or paste the full <:name:id> form." ]
  rescue Discord::BotApi::Error
    [ nil, "Couldn't look up this server's emotes right now — try again in a moment." ]
  end

  # Role/channel pickers come from Discord over REST (bot token), cached
  # briefly. Empty lists (API down / bot missing) block creation safely.
  def load_discord_options
    api = Discord::BotApi.new
    @role_options = Rails.cache.fetch("discord/role_options/#{@guild.id}", expires_in: 60.seconds) do
      api.guild_roles(@guild.id)
         .reject { |r| r["managed"] || r["id"].to_s == @guild.id.to_s } # bot-managed roles + @everyone
         .sort_by { |r| -r["position"].to_i }
         .map { |r| [ r["name"], r["id"].to_s ] }
    end
    @channel_options = Rails.cache.fetch("discord/channel_options/#{@guild.id}", expires_in: 60.seconds) do
      api.guild_channels(@guild.id)
         .select { |c| c["type"].to_i.zero? } # text channels
         .sort_by { |c| c["position"].to_i }
         .map { |c| [ "##{c["name"]}", c["id"].to_s ] }
    end
  rescue Discord::BotApi::Error => e
    Rails.logger.warn("[web] loading Discord options failed for guild #{@guild.id}: #{e.class}: #{e.message}")
    @role_options = []
    @channel_options = []
  end

  # The submitted ids must come from the fetched lists — rejects hand-crafted
  # POSTs pointing the bot at arbitrary roles/channels.
  def valid_discord_choices?
    role_ids = @role_options.map(&:last)
    @channel_options.map(&:last).include?(@team.review_channel_id.to_s) &&
      role_ids.include?(@team.team_role_id.to_s) &&
      role_ids.include?(@team.officer_role_id.to_s)
  end
end
