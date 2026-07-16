class User < ApplicationRecord
  validates :discord_id, presence: true, uniqueness: true

  def self.from_omniauth(auth)
    user = find_or_initialize_by(discord_id: auth.uid)
    raw = auth.extra&.raw_info || {}
    user.username    = auth.info&.name.presence || raw["username"].to_s
    user.global_name = raw["global_name"].presence || user.username
    user.avatar      = avatar_url_from(auth.uid, raw["avatar"])
    user.save!
    user
  end

  def display_name = global_name.presence || username

  def avatar_url = avatar.presence

  # omniauth-discord's info.image omits the file extension, which Discord's CDN
  # rejects — build the URL ourselves (animated avatars start with "a_").
  def self.avatar_url_from(uid, hash)
    return nil if hash.blank?

    ext = hash.to_s.start_with?("a_") ? "gif" : "png"
    "https://cdn.discordapp.com/avatars/#{uid}/#{hash}.#{ext}"
  end
end
