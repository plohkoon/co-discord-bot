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
end
