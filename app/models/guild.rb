class Guild < ApplicationRecord
  self.primary_key = :id

  # Log severity tiers. :high is the important channel owners watch (new
  # applications, unanswered auto-rejects); :low is the mundane audit trail
  # (accept/reject, member removed, team created).
  LOG_LEVELS = %i[high low].freeze

  has_many :teams, dependent: :destroy
  has_many :team_applications, dependent: :destroy
  has_many :team_categories, dependent: :destroy
  has_many :team_types, dependent: :destroy

  validates :id, presence: true

  # `removed_at` marks guilds the bot was kicked from. The row (and all team
  # data) is kept so everything is back if the bot is re-invited.
  scope :installed, -> { where(removed_at: nil) }
  scope :removed,   -> { where.not(removed_at: nil) }

  # Upsert a guild row from a Discord server (snowflake id + name). Seeing the
  # guild on the gateway proves the bot is in it, so this also clears removed_at.
  def self.sync_from_discord(id:, name: nil)
    guild = find_or_initialize_by(id: id)
    newly_created = guild.new_record?
    guild.name = name if name.present?
    guild.removed_at = nil
    guild.save! if guild.new_record? || guild.changed?
    guild.seed_default_team_types! if newly_created
    guild
  end

  # Every guild starts with the stock team-type list (Manage Server users
  # curate it on the web guild page). Idempotent.
  def seed_default_team_types!
    ActsAsTenant.with_tenant(self) do
      return if TeamType.exists?

      TeamType::DEFAULT_NAMES.each_with_index { |name, i| TeamType.create!(name: name, position: i + 1) }
    end
  end

  # The channel a log at `level` should post to. When only one channel is
  # configured, everything collapses into it (the high channel falls back to
  # the low, and vice versa). Returns nil when neither is set.
  def log_channel_id_for(level)
    case level.to_sym
    when :high then important_log_channel_id || log_channel_id
    when :low  then log_channel_id || important_log_channel_id
    end
  end

  def logging_enabled? = log_channel_id.present? || important_log_channel_id.present?

  def removed? = removed_at.present?

  def mark_removed!
    update!(removed_at: Time.current) unless removed?
  end
end
