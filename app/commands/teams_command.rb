class TeamsCommand < ApplicationCommand
  before_action :require_admin, only: :create

  # /team create
  def create
    team = current_guild.teams.new(
      name: option(:name).to_s.strip,
      team_role_id: option(:role),
      officer_role_id: option(:officer_role),
      review_channel_id: option(:review_channel)
    )

    if team.save
      team.seed_default_questions!
      respond("✅ Created team **#{team.name}**. Members can now `/apply`. " \
              "I added a starter set of application questions — edit them in the dashboard.")
    else
      respond("⚠️ Couldn't create the team: #{team.errors.full_messages.to_sentence}")
    end
  end

  # /team list
  def index
    teams = current_guild.teams.active.order(:name)
    if teams.empty?
      respond("No teams yet. An admin can create one with `/team create`.")
    else
      lines = teams.map do |team|
        "• **#{team.name}** — <@&#{team.team_role_id}> · #{team.team_applications.pending.count} pending"
      end
      respond("**Teams in #{server.name}**\n#{lines.join("\n")}")
    end
  end

  private

  def require_admin
    return if admin?

    respond("⛔ You need the **Manage Server** permission to do that.")
  end

  def admin?
    member = current_user
    member.respond_to?(:permission?) &&
      (member.permission?(:administrator) || member.permission?(:manage_server))
  end
end
