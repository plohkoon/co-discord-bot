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
  # Viewing the team page is public; submitting is not. An anonymous POST is
  # bounced into the login flow (no return_to — a lost POST can't be replayed)
  # and creates nothing.
  before_action :require_login, only: :create

  def new
    load_form_state
  end

  def create
    unless @team.recruiting?
      return redirect_to public_team_path(@guild.slug, @team.slug), alert: @team.resolved_closed_message
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
    redirect_to public_team_path(@guild.slug, @team.slug), notice: confirmation_notice
  rescue Applications::Submit::DuplicatePending
    redirect_to public_team_path(@guild.slug, @team.slug), alert: "You already have a pending application to #{@team.name}."
  rescue Applications::Submit::AlreadyMember
    redirect_to public_team_path(@guild.slug, @team.slug), alert: "You're already a member of #{@team.name}."
  end

  private

  def set_team
    @team = Team.active.find_by(slug: params[:team_slug])
    redirect_to public_guild_path(@guild.slug), alert: "That team doesn't exist." if @team.nil?
  end

  def load_form_state
    @questions = @team.application_questions.ordered.to_a
    # Prior answers for re-rendering the form after a validation miss. Read
    # through the shape-safe accessor rather than raw params, so a crafted
    # non-hash `application` param can't blow up the view either.
    @submitted = submitted_values
    # Looked up for every signed-in visitor — a non-member may already have a
    # pending application (that's the whole apply-before-joining flow), and the
    # page must show its state rather than offer the form again. Anonymous
    # visitors have no membership to look up (they see the sign-in CTA).
    @membership = TeamMembership.find_by(team_id: @team.id, discord_user_id: current_user.discord_id) if logged_in?
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
  # permit-everything over raw params. The Discord modal path gets its length
  # caps from Discord itself; this path has no modal, so the caps are enforced
  # here (per-question max, falling back to the field ceiling) — otherwise an
  # anonymous POST could store an unbounded answer. `character` is clamped to
  # Discord's modal input width, matching the collect-character slot.
  CHARACTER_INPUT_MAX = 100

  def submitted_values
    # A legit nested `application[q:1]=…` parses to ActionController::Parameters;
    # a crafted `application[]=x` parses to an Array (whose #[] takes an Integer,
    # not a String). Coerce anything but Parameters to empty so an odd shape is
    # a validation miss, not a 500.
    raw = params[:application]
    form = raw.is_a?(ActionController::Parameters) ? raw : {}
    values = @team.application_questions.ordered.to_h do |q|
      [ "q:#{q.id}", clamp(form["q:#{q.id}"], q.max_length || ApplicationQuestion::VALUE_MAX) ]
    end
    values["character"] = clamp(form["character"], CHARACTER_INPUT_MAX) if @team.collect_character?
    values
  end

  def clamp(value, limit) = value.to_s[0, limit].to_s
end
