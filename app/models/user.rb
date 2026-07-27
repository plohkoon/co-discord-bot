class User < ApplicationRecord
  # Discord ids of app-wide admins (the /admin panel and job dashboard).
  # Deliberately hardcoded: admin cannot be granted through the web app.
  ADMIN_DISCORD_IDS = %w[99235095214313472].freeze

  validates :discord_id, presence: true, uniqueness: true

  # Battle.net links are per-person, not per-guild: link once, works in every
  # server co-bot is in.
  has_many :battle_net_accounts, dependent: :destroy
  # Direct, not through battle_net_accounts: a character can be claimed without
  # any Battle.net link at all.
  has_many :wow_characters, dependent: :nullify

  # --- The Discord bridge ---
  #
  # The bot identifies people by raw snowflake, because a Discord interaction is
  # all it ever has. `discord_user_id` on those tables and `discord_id` here are
  # the same number, so they join on it directly — the same natural-key pattern
  # the WoW satellites use, and it avoids a second identity column that could
  # drift from the first.
  #
  # NOT guild-scoped: these return the person's memberships across every server,
  # which is the question worth asking of a person rather than of a tenant.
  has_many :team_memberships, foreign_key: :discord_user_id, primary_key: :discord_id,
                              inverse_of: :user, dependent: nil
  has_many :team_applications, foreign_key: :discord_user_id, primary_key: :discord_id,
                               inverse_of: :user, dependent: nil

  # Servers where the user has Manage Server but co-bot isn't installed,
  # captured at login ({"id","name","icon"} hashes). Kept on the row instead of
  # the session so the dashboard can offer "Add co-bot" without overflowing the
  # 4KB cookie. Refreshed on every sign-in.
  serialize :installable_guilds, coder: JSON, type: Array

  # A signed-in person. Adopts an existing shadow row when there is one — the
  # find_or_initialize is what makes "applied in Discord, signed in later"
  # converge on one record instead of two.
  def self.from_omniauth(auth)
    user = find_or_initialize_by(discord_id: auth.uid)
    raw = auth.extra&.raw_info || {}
    user.username    = auth.info&.name.presence || raw["username"].to_s
    user.global_name = raw["global_name"].presence || user.username
    user.avatar      = avatar_url_from(auth.uid, raw["avatar"])
    user.authenticated_at = Time.current
    user.save!
    user
  end

  # The person behind a Discord interaction, creating a shadow record if this is
  # the first co-bot has heard of them.
  #
  # Called from bot-side flows where all we have is a snowflake — someone
  # applying to a team and naming a character, for instance. The row exists so
  # that person can *own* things; it asserts nothing about who they are, which
  # is what `authenticated_at` records.
  def self.for_discord(discord_id, username: nil)
    user = find_or_initialize_by(discord_id: discord_id)
    # Never overwrite a name from a real sign-in with one from an interaction
    # payload; do fill it in for a shadow row that has none.
    user.username = username.to_s if username.present? && user.username.blank?
    user.global_name = user.username if user.global_name.blank?
    user.save!
    user
  end

  # Has this person ever actually signed in? A shadow record can hold characters
  # and join to memberships, but it has proved nothing.
  def authenticated? = authenticated_at.present?

  def shadow? = !authenticated?

  def admin? = ADMIN_DISCORD_IDS.include?(discord_id.to_s)

  # --- Battle.net ---

  def linked_battle_net? = battle_net_accounts.any?

  # Discord told us they've linked Battle.net but they haven't proved it to us —
  # the prompt worth showing on the account page.
  def battle_net_link_suggested? = discord_battle_tag.present? && !linked_battle_net?

  # Refresh what Discord reports the user has connected on their side. Called at
  # sign-in; a user who unlinks in Discord clears the columns here too.
  def record_discord_connections!(connections)
    battle_net = Array(connections).find { |c| c.type == Discord::Connections::BATTLE_NET && c.verified? }
    update!(
      discord_battle_net_id: battle_net&.id.presence,
      discord_battle_tag: battle_net&.name.presence
    )
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
