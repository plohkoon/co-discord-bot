class User < ApplicationRecord
  # Discord ids of app-wide admins (the /admin panel and job dashboard).
  # Deliberately hardcoded: admin cannot be granted through the web app.
  ADMIN_DISCORD_IDS = %w[99235095214313472].freeze

  validates :discord_id, presence: true, uniqueness: true

  # Servers where the user has Manage Server but co-bot isn't installed,
  # captured at login ({"id","name","icon"} hashes). Kept on the row instead of
  # the session so the dashboard can offer "Add co-bot" without overflowing the
  # 4KB cookie. Refreshed on every sign-in.
  serialize :installable_guilds, coder: JSON, type: Array

  def self.from_omniauth(auth)
    user = find_or_initialize_by(discord_id: auth.uid)
    raw = auth.extra&.raw_info || {}
    user.username    = auth.info&.name.presence || raw["username"].to_s
    user.global_name = raw["global_name"].presence || user.username
    user.avatar      = avatar_url_from(auth.uid, raw["avatar"])
    user.save!
    user
  end

  def admin? = ADMIN_DISCORD_IDS.include?(discord_id.to_s)

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
