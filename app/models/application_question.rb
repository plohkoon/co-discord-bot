class ApplicationQuestion < ApplicationRecord
  include GuildScoped

  # Discord modal limits: at most 5 inputs, label <= 45 chars, placeholder
  # <= 100 chars, and text value length 0..4000.
  MAX_PER_TEAM    = 5
  LABEL_MAX       = 45
  PLACEHOLDER_MAX = 100
  VALUE_MAX       = 4000

  belongs_to :team

  enum :style, { short: 0, paragraph: 1 }, default: :short

  validates :key, presence: true, uniqueness: { scope: :team_id }
  validates :label, presence: true, length: { maximum: LABEL_MAX }
  validates :placeholder, length: { maximum: PLACEHOLDER_MAX }, allow_blank: true
  validates :min_length, numericality: { only_integer: true, in: 0..VALUE_MAX }, allow_nil: true
  validates :max_length, numericality: { only_integer: true, in: 1..VALUE_MAX }, allow_nil: true
  validate  :min_not_greater_than_max
  validate  :within_team_limit, on: :create

  scope :ordered, -> { order(:position) }

  private

  def min_not_greater_than_max
    return if min_length.blank? || max_length.blank?

    errors.add(:min_length, "can't be greater than the max length") if min_length > max_length
  end

  def within_team_limit
    return if team.blank?

    if team.application_questions.where.not(id: id).count >= MAX_PER_TEAM
      errors.add(:base, "a team can have at most #{MAX_PER_TEAM} application questions")
    end
  end
end
