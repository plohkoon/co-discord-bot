class ApplicationQuestion < ApplicationRecord
  include GuildScoped

  # Discord modal limits: at most 5 inputs, label <= 45 chars, description
  # (shown beneath the label) <= 100 chars, placeholder <= 100 chars, and text
  # value length 0..4000. The description is where a question too long for the
  # label goes: a short label, with the full prompt underneath.
  MAX_PER_TEAM    = 5
  LABEL_MAX       = 45
  DESCRIPTION_MAX = 100
  PLACEHOLDER_MAX = 100
  VALUE_MAX       = 4000

  # Choice questions (Discord's Radio Group / Checkbox Group modal components):
  # an option's label doubles as its value, and both cap at 100 chars. A radio
  # group needs 2–10 options; a checkbox group 1–10.
  OPTION_MAX       = 100
  OPTIONS_MAX      = 10
  CHOICE_MIN       = 2
  CHECKBOXES_MIN   = 1
  CHECKBOXES_JOINER = ", "

  YES = "Yes"
  NO  = "No"

  belongs_to :team

  # short/paragraph: a Text Input. choice: a Radio Group (pick exactly one).
  # checkboxes: a Checkbox Group (tick any). yes_no: a single Checkbox —
  # Discord can't make one required, so a yes/no question never is: unticked
  # simply answers "No".
  enum :style, { short: 0, paragraph: 1, choice: 2, checkboxes: 3, yes_no: 4 }, default: :short

  STYLE_LABELS = {
    "short" => "Short text",
    "paragraph" => "Paragraph",
    "choice" => "Multiple choice",
    "checkboxes" => "Checkboxes",
    "yes_no" => "Yes / No"
  }.freeze

  serialize :options, coder: JSON, type: Array

  # Each style keeps only the settings it uses, so switching a question from
  # text to choice (or back) never leaves stale limits or options behind that
  # the modal would then be built with.
  before_validation :drop_settings_the_style_ignores

  validates :key, presence: true, uniqueness: { scope: :team_id }
  validates :label, presence: true, length: { maximum: LABEL_MAX }
  validates :description, length: { maximum: DESCRIPTION_MAX }, allow_blank: true
  validates :placeholder, length: { maximum: PLACEHOLDER_MAX }, allow_blank: true
  validates :min_length, numericality: { only_integer: true, in: 0..VALUE_MAX }, allow_nil: true
  validates :max_length, numericality: { only_integer: true, in: 1..VALUE_MAX }, allow_nil: true
  validate  :min_not_greater_than_max
  validate  :options_fit_style
  validate  :within_team_limit, on: :create

  scope :ordered, -> { order(:position) }

  def self.style_options = STYLE_LABELS.map { |value, label| [ label, value ] }

  def text? = short? || paragraph?
  def multiple_choice? = choice? || checkboxes?

  # The web editor takes options one per line.
  def options_text = Array(options).join("\n")

  def options_text=(text)
    self.options = text.to_s.lines.map(&:strip).reject(&:empty?).uniq
  end

  # The answer as it's stored and shown to officers, read from either a
  # Discord modal submit or Applications::WebSubmission (both answer
  # `value(key)` / `values(key)`). Choices are kept only if they're still one
  # of the question's options, so a crafted web POST — or an option edited
  # away between opening the modal and submitting it — can't record an answer
  # nobody was offered.
  def answer_from(source)
    key = "q:#{id}"
    case style
    when "choice"     then offered([ source.value(key) ]).first.to_s
    when "checkboxes" then offered(Array(source.values(key))).join(CHECKBOXES_JOINER)
    when "yes_no"     then ticked?(source.value(key)) ? YES : NO
    else source.value(key).to_s
    end
  end

  private

  def offered(picked) = Array(options) & picked.map(&:to_s)

  # Discord sends the checkbox as a boolean; the web form as "1"/"0".
  def ticked?(value) = [ true, "1", "true" ].include?(value)

  def drop_settings_the_style_ignores
    self.options = [] unless multiple_choice?
    self.required = false if yes_no?
    return if text?

    self.placeholder = nil
    self.min_length = nil
    self.max_length = nil
  end

  def options_fit_style
    return unless multiple_choice?

    minimum = choice? ? CHOICE_MIN : CHECKBOXES_MIN
    count = Array(options).size
    if count < minimum || count > OPTIONS_MAX
      errors.add(:options, "need #{minimum}–#{OPTIONS_MAX} for #{STYLE_LABELS[style].downcase} (one per line)")
    end
    if Array(options).any? { |option| option.length > OPTION_MAX }
      errors.add(:options, "can each be at most #{OPTION_MAX} characters")
    end
  end

  def min_not_greater_than_max
    return if min_length.blank? || max_length.blank?

    errors.add(:min_length, "can't be greater than the max length") if min_length > max_length
  end

  def within_team_limit
    return if team.blank?

    # The team's own limit, not the raw modal cap: asking for a character costs
    # one of Discord's five slots, so a team that collects one has room for four
    # questions.
    limit = team.question_limit
    return if team.application_questions.where.not(id: id).count < limit

    errors.add(:base, if limit < MAX_PER_TEAM
      "a team that asks for a character can have at most #{limit} application questions"
    else
      "a team can have at most #{limit} application questions"
    end)
  end
end
