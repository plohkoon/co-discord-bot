class TeamMembership < ApplicationRecord
  include GuildScoped

  belongs_to :team
  # The person, when co-bot has a record of them. Joined on the snowflake the
  # bot already stores rather than a second identity column that could drift
  # from it — the same natural-key pattern the WoW satellites use.
  #
  # Optional, and nil is the COMMON case: a member who has never signed into the
  # web app and never claimed a character has no users row at all. Treat nil as
  # "unknown", never as "has nothing".
  belongs_to :user, foreign_key: :discord_user_id, primary_key: :discord_id,
                    inverse_of: :team_memberships, optional: true
  # The character they play ON THIS TEAM. Distinct from their main because it
  # genuinely differs — people main a tank and raid as a healer, or bring an alt
  # to the second team. Seeded from the application, changeable by the leads.
  belongs_to :wow_character, optional: true
  has_many :team_applications, dependent: :nullify
  has_many :membership_notes, -> { order(created_at: :desc) }, dependent: :destroy
  has_many :absences, dependent: :nullify

  enum :status, { pending: 0, active: 1, archived: 2 }, default: :pending

  validates :discord_user_id, presence: true
  validates :discord_user_id, uniqueness: { scope: :team_id }

  scope :recent, -> { order(updated_at: :desc) }
  scope :matching, ->(query) { query.to_s.strip.present? ? where("discord_username LIKE ?", "%#{query.to_s.strip}%") : all }

  def mention = "<@#{discord_user_id}>"

  # The current undecided application, if any.
  def open_application = team_applications.pending.order(created_at: :desc).first
end
