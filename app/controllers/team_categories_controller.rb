# Manage Server CRUD for the guild's roster categories (directory section
# headers). Teams pick from this list — categories are never created on the
# fly from a team form or command. Renames, reorders, about text, and the
# "Apply to make a team" toggle show up in any posted roster via
# RosterRefreshJob.
class TeamCategoriesController < ApplicationController
  include GuildScoping
  before_action :require_guild_manager

  def create
    category = TeamCategory.new(category_params)
    if category.save
      # Unfiltered rosters show every category, so a new one appears there
      # straight away. Skipped (rather than left to no-op) when nothing's posted.
      RosterRefreshJob.perform_later(guild_id: @guild.id) if RosterPost.exists?
      redirect_to guild_path(@guild), notice: "Category added."
    else
      redirect_to guild_path(@guild), alert: category.errors.full_messages.to_sentence
    end
  end

  def update
    category = TeamCategory.find(params[:id])
    if category.update(category_params)
      RosterRefreshJob.perform_later(guild_id: @guild.id)
      redirect_to guild_path(@guild), notice: "Category updated."
    else
      redirect_to guild_path(@guild), alert: category.errors.full_messages.to_sentence
    end
  end

  def destroy
    TeamCategory.find(params[:id]).destroy # its teams stay, uncategorized
    RosterRefreshJob.perform_later(guild_id: @guild.id)
    redirect_to guild_path(@guild), notice: "Category removed. Its teams are now uncategorized."
  end

  private

  def category_params
    attrs = params.require(:team_category).permit(:name, :position, :about, :proposals_enabled)
    # Inline emote resolution: known :name: shortcodes render in the roster's
    # "## Category" header and about text; unknown ones stay as typed.
    %i[name about].each do |key|
      attrs[key] = Discord::EmoteResolver.resolve_text(guild_id: @guild.id, input: attrs[key]) if attrs[key].present?
    end
    attrs
  end
end
