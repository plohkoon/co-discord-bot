# Per-team public apply page (/apply/:guild_id/teams/:team_id — the direct
# link an officer shares) and the web application submit. Submission goes
# through Applications::Submit — the same service as the Discord modal — via
# the WebSubmission adapter, so the business rules can't fork.
# Membership in the Discord server is deliberately NOT required to submit —
# applying before joining is the intended recruiting flow (accepted outsiders
# get their role from MemberJoinReconcileJob when they join). Non-members see
# the join banner here and a join reminder in the confirmation instead.
class PublicApplicationsController < PublicBaseController
  before_action :set_team

  def new
    load_form_state
  end

  def create
    unless @team.recruiting?
      return redirect_to public_team_path(@guild.id, @team), alert: @team.resolved_closed_message
    end

    values = submitted_values
    missing = required_questions.select { |q| values["q:#{q.id}"].blank? }
    if missing.any?
      # The browser enforces `required`, so this only catches hand-crafted
      # POSTs — but the modal path enforces it server-side (Discord does), and
      # the web path must not be the weaker one.
      flash.now[:alert] = "Please answer: #{missing.map(&:label).join(', ')}."
      load_form_state
      return render :new, status: :unprocessable_entity
    end

    Applications::Submit.call(team: @team, event: Applications::WebSubmission.new(user: current_user, values: values))
    redirect_to public_team_path(@guild.id, @team), notice: confirmation_notice
  rescue Applications::Submit::DuplicatePending
    redirect_to public_team_path(@guild.id, @team), alert: "You already have a pending application to #{@team.name}."
  rescue Applications::Submit::AlreadyMember
    redirect_to public_team_path(@guild.id, @team), alert: "You're already a member of #{@team.name}."
  end

  private

  def set_team
    @team = Team.active.find_by(id: params[:team_id])
    redirect_to public_guild_path(@guild.id), alert: "That team doesn't exist." if @team.nil?
  end

  def load_form_state
    @questions = @team.application_questions.ordered.to_a
    # Looked up for everyone — a non-member may already have a pending
    # application (that's the whole apply-before-joining flow), and the page
    # must show its state rather than offer the form again.
    @membership = TeamMembership.find_by(team_id: @team.id, discord_user_id: current_user.discord_id)
  end

  # The join reminder rides the confirmation for applicants who aren't in the
  # server yet — the page they land on also shows the join banner (with the
  # invite button) up top.
  def confirmation_notice
    if guild_member?
      "Application sent — #{@team.name}'s officers have been notified. You'll get a Discord DM confirming it."
    else
      "Application sent — make sure you join the Discord server so we can add you to the team when you're accepted."
    end
  end

  def required_questions
    @team.application_questions.ordered.select(&:required)
  end

  # Only the keys the form legitimately owns, read explicitly — never a
  # permit-everything over raw params.
  def submitted_values
    form = params.fetch(:application, {})
    values = @team.application_questions.ordered.to_h { |q| [ "q:#{q.id}", form["q:#{q.id}"].to_s ] }
    values["character"] = form["character"].to_s if @team.collect_character?
    values
  end
end
