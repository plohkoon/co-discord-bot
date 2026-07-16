class Guild < ApplicationRecord
  self.primary_key = :id

  has_many :teams, dependent: :destroy
  has_many :team_applications, dependent: :destroy

  validates :id, presence: true

  # Upsert a guild row from a Discord server (snowflake id + name).
  def self.sync_from_discord(id:, name: nil)
    guild = find_or_initialize_by(id: id)
    guild.name = name if name.present?
    guild.save! if guild.new_record? || guild.changed?
    guild
  end
end
