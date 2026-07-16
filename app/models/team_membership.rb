class TeamMembership < ApplicationRecord
  include GuildScoped

  belongs_to :team
  has_many :team_applications, dependent: :nullify
  has_many :membership_notes, -> { order(created_at: :desc) }, dependent: :destroy

  enum :status, { pending: 0, active: 1, archived: 2 }, default: :pending

  validates :discord_user_id, presence: true
  validates :discord_user_id, uniqueness: { scope: :team_id }

  scope :recent, -> { order(updated_at: :desc) }
  scope :matching, ->(query) { query.to_s.strip.present? ? where("discord_username LIKE ?", "%#{query.to_s.strip}%") : all }

  def mention = "<@#{discord_user_id}>"

  # The current undecided application, if any.
  def open_application = team_applications.pending.order(created_at: :desc).first
end
