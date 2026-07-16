class TeamApplication < ApplicationRecord
  include GuildScoped

  belongs_to :team
  has_many :application_answers, -> { order(:position) }, dependent: :destroy

  enum :status, { pending: 0, accepted: 1, rejected: 2 }, default: :pending

  validates :discord_user_id, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def applicant_mention = "<@#{discord_user_id}>"

  def decided? = accepted? || rejected?
end
