class Team < ApplicationRecord
  include GuildScoped

  belongs_to :team_category, optional: true
  belongs_to :team_type, optional: true
  has_many :application_questions, -> { order(:position) }, dependent: :destroy
  has_many :team_applications, dependent: :destroy
  has_many :team_memberships, dependent: :destroy
  has_many :team_officers, dependent: :delete_all

  # Free-form roster details shown in the /team roster directory (and the web
  # team page). All optional; rendered verbatim. `emote` decorates the heading
  # (unicode or <:custom:id>); the rest are lines. The team-type line is NOT
  # free-form — it's picked from the guild's curated TeamType list.
  ROSTER_FIELDS = %i[emote progression requirements date_and_time current_needs].freeze

  # Per-team DM acknowledgements. Nullable — a blank column falls back to the
  # matching DEFAULT_* below. {team}/{user} are substituted at send time (see
  # resolved_*_response), not saved expanded, so a rename keeps working.
  MESSAGE_FIELDS = %i[apply_response absence_response].freeze

  DEFAULT_APPLY_RESPONSE =
    "Thanks {user}! Your application to {team} is in — the team's been notified and will get back to you soon.".freeze
  DEFAULT_ABSENCE_RESPONSE =
    "Thanks {user} — your absence for {team} has been recorded. See you next time!".freeze

  validates :name, presence: true, length: { maximum: 100 }
  validates_uniqueness_to_tenant :name, case_sensitive: false
  validates :team_role_id, :officer_role_id, :review_channel_id, presence: true

  scope :active, -> { where(active: true) }
  scope :matching, ->(query) { query.to_s.strip.present? ? where("name LIKE ?", "%#{query.to_s.strip}%") : all }

  # Sensible starter questions created with a new team; admins can edit them
  # later via the web dashboard.
  DEFAULT_QUESTIONS = [
    { key: "handle",     label: "In-game name / handle",    style: :short,     required: true,  placeholder: "How should we refer to you?" },
    { key: "timezone",   label: "Timezone",                 style: :short,     required: true,  placeholder: "e.g. UTC-5 / EST" },
    { key: "experience", label: "Relevant experience",      style: :paragraph, required: false, placeholder: "A bit about your background" },
    { key: "why",        label: "Why do you want to join?", style: :paragraph, required: true }
  ].freeze

  def seed_default_questions!
    return if application_questions.exists?

    DEFAULT_QUESTIONS.each_with_index do |attrs, i|
      application_questions.create!(position: i, **attrs)
    end
  end

  # DM sent to an applicant when they apply. The stored template (or the
  # default) with {team} -> name and {user} -> the caller-supplied mention.
  def resolved_apply_response(user_mention:)
    render_message(apply_response.presence || DEFAULT_APPLY_RESPONSE, user_mention:)
  end

  # DM for the (not-yet-shipped) attendance flow — same substitution.
  def resolved_absence_response(user_mention:)
    render_message(absence_response.presence || DEFAULT_ABSENCE_RESPONSE, user_mention:)
  end

  private

  # Single-pass substitution so a team name that itself contains "{user}" can't
  # be re-expanded, and so a stray backslash in the name isn't read as a gsub
  # backreference.
  def render_message(template, user_mention:)
    template.to_s.gsub(/\{(team|user)\}/) { Regexp.last_match(1) == "team" ? name.to_s : user_mention.to_s }
  end
end
