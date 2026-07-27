class TeamApplication < ApplicationRecord
  include GuildScoped

  belongs_to :team
  belongs_to :team_membership, optional: true
  # See TeamMembership#user — same snowflake join, same "nil means unknown".
  belongs_to :user, foreign_key: :discord_user_id, primary_key: :discord_id,
                    inverse_of: :team_applications, optional: true
  # What they applied on. `character_input` keeps what they typed even on
  # success, because it is the only evidence of intent when resolution fails.
  belongs_to :wow_character, optional: true
  has_many :application_answers, -> { order(:position) }, dependent: :destroy

  # They named a character and Blizzard didn't recognise it — a typo, almost
  # always. Worth surfacing to both the applicant and the reviewer rather than
  # silently showing no character at all.
  def character_unresolved? = character_input.present? && wow_character_id.nil?

  def character_asked? = character_input.present?

  enum :status, { pending: 0, accepted: 1, rejected: 2 }, default: :pending
  enum :source, { applied: 0, manual: 1 }, default: :applied

  validates :discord_user_id, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def applicant_mention = "<@#{discord_user_id}>"

  def decided? = accepted? || rejected?

  # Parked by a lead: the daily digest skips it and its 7-day deadline stops
  # running. Deciding an application ends the pause implicitly, which also
  # settles the (tiny) race between a pause and the sweep claiming the row.
  def paused? = pending? && paused_at.present?

  # The clock Applications::ReviewDigest measures against — both the "waiting N
  # days" line and the auto-reject deadline. Resuming a paused application
  # restarts it, so it diverges from created_at.
  def timeline_start = timeline_started_at || created_at
end
