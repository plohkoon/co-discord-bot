class User < ApplicationRecord
  validates :discord_id, presence: true, uniqueness: true

  def self.from_omniauth(auth)
    user = find_or_initialize_by(discord_id: auth.uid)
    raw = auth.extra&.raw_info || {}
    user.username    = auth.info&.name.presence || raw["username"].to_s
    user.global_name = raw["global_name"].presence || user.username
    user.avatar      = auth.info&.image
    user.save!
    user
  end

  def display_name = global_name.presence || username

  def avatar_url = avatar.presence
end
