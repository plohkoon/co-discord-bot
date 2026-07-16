class ApplyCommand < ApplicationCommand
  # /apply — open the application modal for the chosen team
  def new
    team = resolve_team(option(:team))
    return respond("Pick a team from the list.") unless team
    return respond("You already have a pending application to **#{team.name}**.") if pending_for?(team)

    questions = team.application_questions.ordered.to_a
    return respond("**#{team.name}** has no application questions set up yet.") if questions.empty?

    show_modal(title: "Apply — #{team.name}", custom_id: CoBot::Router.custom_id("apply", team.id)) do |modal|
      questions.each do |question|
        modal.label(label: question.label) do |label|
          label.text_input(
            style: question.paragraph? ? :paragraph : :short,
            custom_id: "q:#{question.id}",
            required: question.required,
            min_length: question.min_length,
            max_length: question.max_length,
            placeholder: question.placeholder.presence
          )
        end
      end
    end
  end

  # Autocomplete for the `team` option of /apply
  def autocomplete
    typed = option(:team).to_s
    teams = current_guild.teams.active.order(:name)
    teams = teams.where("name LIKE ?", "%#{typed}%") if typed.present?
    choices = teams.limit(25).each_with_object({}) { |team, acc| acc[team.name] = team.id.to_s }
    event.respond(choices: choices)
  end

  # Modal submit — record the application and post it to the review channel
  def create
    team = current_guild.teams.find_by(id: params[:team_id])
    return respond("That team no longer exists.") unless team

    application = Applications::Submit.call(team: team, event: event)
    respond("✅ Your application to **#{team.name}** was submitted! The team's officers will review it.")
    CoBot::ReviewMessage.post(bot: event.bot, team: team, application: application)
  rescue Applications::Submit::AlreadyMember
    respond("You're already a member of **#{team.name}**.")
  rescue Applications::Submit::DuplicatePending
    respond("You already have a pending application to **#{team.name}**.")
  end

  # Accept/Reject button — decide, and on accept assign the team role
  def decide
    application = current_guild.team_applications.find_by(id: params[:application_id])
    return respond("That application no longer exists.") unless application

    unless officer_for?(application.team)
      return respond("Only **#{application.team.name}** officers can review this application.")
    end

    result = Applications::Decide.call(
      application: application,
      decision: params[:decision],
      decided_by_discord_id: current_user_id,
      role_granter: ->(app) { grant_team_role(app) }
    )

    case result.status
    when :already_decided
      respond("This application was already handled by someone else.")
    when :error
      respond("⚠️ #{result.error}")
    else
      update_message(embeds: [ CoBot::ReviewMessage.decided_embed(application.reload) ], components: [])
    end
  end

  private

  # Only a team's officers (or server admins) may accept/reject its applications.
  # Defence-in-depth on top of restricting the review channel's visibility.
  def officer_for?(team)
    member = current_user
    return false unless member.respond_to?(:roles)

    member.permission?(:administrator) || member.permission?(:manage_server) ||
      member.roles.any? { |role| role.id == team.officer_role_id }
  end

  def resolve_team(raw)
    raw = raw.to_s
    scope = current_guild.teams.active
    raw.match?(/\A\d+\z/) ? scope.find_by(id: raw) : scope.where("name LIKE ?", raw).first
  end

  def pending_for?(team)
    team.team_applications.pending.where(discord_user_id: current_user_id).exists?
  end

  # Assign the team role to the applicant. Raises Applications::Decide::RoleError
  # (handled by Decide as a compensating revert) if we can't.
  def grant_team_role(application)
    team = application.team
    role = server.role(team.team_role_id)
    raise Applications::Decide::RoleError, "the team role no longer exists" unless role

    me = server.member(event.bot.profile.id)
    raise Applications::Decide::RoleError, "I couldn't find my own membership in this server" unless me

    unless me.permission?(:manage_roles) || me.permission?(:administrator)
      raise Applications::Decide::RoleError, "I need the **Manage Roles** permission"
    end
    if me.highest_role.position <= role.position
      raise Applications::Decide::RoleError, "my highest role must be above **#{role.name}** (Server Settings → Roles)"
    end

    member = server.member(application.discord_user_id)
    raise Applications::Decide::RoleError, "the applicant has left the server" unless member

    member.add_role(role, "Accepted to #{team.name} via co-bot")
  end
end
