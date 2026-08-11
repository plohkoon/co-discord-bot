# Per-team public apply page (/apply/:guild_id/teams/:team_id — the direct
# link an officer shares) and the web application submit. Submission goes
# through Applications::Submit — the same service as the Discord modal — via
# the WebSubmission adapter, so the business rules can't fork.
# Membership in the Discord server is deliberately NOT required to submit —
# applying before joining is the intended recruiting flow (accepted outsiders
# get their role from MemberJoinReconcileJob when they join). Non-members see
# the join banner here and a join reminder in the confirmation instead.
class PublicApplicationsController < PublicBaseController
  # Resolves the rate-limit counter store at request time rather than binding
  # it at class-load. Rails 8's `rate_limit` captures `store:` once, when the
  # class body runs — in the test env that would freeze onto the :null_store
  # (whose #increment always returns nil, silently no-opping the limiter),
  # making the limit both untestable and inert. Delegating to Rails.cache per
  # request tracks the live store (Solid Cache in production) and lets a test
  # swap in a real store for the one case that exercises the limit.
  LAZY_RATE_LIMIT_STORE = Object.new.tap do |store|
    def store.increment(...) = Rails.cache.increment(...)
  end
  private_constant :LAZY_RATE_LIMIT_STORE

  before_action :set_team
  # Viewing the team page is public; submitting is not. An anonymous POST is
  # bounced into the login flow (no return_to — a lost POST can't be replayed)
  # and creates nothing.
  before_action :require_login, only: :create
  # Throttle submissions per signed-in user. This runs AFTER require_login, so
  # anonymous POSTs are already bounced (and never counted) and current_user is
  # present. Slugs are enumerable, so one account could otherwise walk every
  # team and spam each officer channel — a human applies to a handful of teams,
  # 5/min is generous for that and punishing for a script.
  rate_limit to: 5, within: 1.minute,
             by: -> { current_user&.id },
             store: LAZY_RATE_LIMIT_STORE,
             with: -> { redirect_to public_team_path(@guild.slug, @team.slug), alert: "You're applying too fast — give it a minute and try again." },
             only: :create

  def new
    load_form_state
  end

  def create
    unless @team.recruiting?
      return redirect_to public_team_path(@guild.slug, @team.slug), alert: @team.resolved_closed_message
    end

    # Pre-check mirroring the bot's /team apply guard (Commands::ApplyFlow): an
    # active member can't re-apply, and an open application (pending — which
    # includes a lead-paused one, still status pending) can't be duplicated.
    # This surfaces a friendly message instead of leaning on the DB unique
    # index; Submit's DuplicatePending/AlreadyMember below remain the backstop
    # for the race between this check and the insert. Looked up by discord id,
    # so a non-member with an open application is blocked just the same.
    membership = TeamMembership.find_by(team_id: @team.id, discord_user_id: current_user.discord_id)
    if membership&.active?
      return redirect_to public_team_path(@guild.slug, @team.slug), alert: "You're already a member of #{@team.name}."
    end
    if membership&.open_application
      return redirect_to public_team_path(@guild.slug, @team.slug), alert: "You already have a pending application to #{@team.name} — it's awaiting review."
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
  # permit-everything over raw params.
  def submitted_values
    form = params.fetch(:application, {})
    values = @team.application_questions.ordered.to_h { |q| [ "q:#{q.id}", form["q:#{q.id}"].to_s ] }
    values["character"] = form["character"].to_s if @team.collect_character?
    values
  end
end
