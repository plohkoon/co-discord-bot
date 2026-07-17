class TeamsController < ApplicationController
  # GuildScoping already limits every action here to users who hold Manage
  # Server on the guild (verified against Discord at login).
  include GuildScoping

  def new
    @team = @guild.teams.new
    load_discord_options
  end

  def create
    attrs = params.require(:team).permit(:name, :team_role_id, :officer_role_id, :review_channel_id,
                                         :position, :category_name, *Team::ROSTER_FIELDS)
    category_name = attrs.delete(:category_name)
    @team = @guild.teams.new(attrs)
    @team.team_category = TeamCategory.locate(category_name)

    load_discord_options
    unless valid_discord_choices?
      flash.now[:alert] = "Pick the team role, officer role, and review channel from the lists."
      return render :new, status: :unprocessable_entity
    end

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
    @questions = @team.application_questions.ordered
    @new_question = @team.application_questions.build(required: true)

    memberships = @team.team_memberships.order(updated_at: :desc).to_a
    @members_by_status = memberships.group_by(&:status)
    @counts = %w[active pending archived].index_with { |status| @members_by_status[status]&.size || 0 }
    @app_counts = TeamApplication.where(team_membership_id: memberships.map(&:id)).group(:team_membership_id).count
  end

  # Roster details (category + the free-form lines shown by /team roster).
  def update
    @team = @guild.teams.find(params[:id])
    attrs = params.require(:team).permit(:category_name, :position, *Team::ROSTER_FIELDS)
    category_name = attrs.delete(:category_name)

    @team.assign_attributes(attrs)
    @team.team_category = TeamCategory.locate(category_name) # blank clears it

    if @team.save
      TeamRosterRefreshJob.perform_later(guild_id: @guild.id, team_id: @team.id)
      redirect_to guild_team_path(@guild, @team), notice: "Roster details updated."
    else
      redirect_to guild_team_path(@guild, @team), alert: @team.errors.full_messages.to_sentence
    end
  end

  private

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
