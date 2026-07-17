# The per-guild vocabulary for a team's "type" roster line ("Heroic Team").
# Every guild starts with DEFAULT_NAMES (seeded by Guild.sync_from_discord);
# Manage Server users curate the list on the web guild page, and teams pick
# from it — types are never created on the fly from a team form or command.
class TeamType < ApplicationRecord
  include GuildScoped

  DEFAULT_NAMES = [ "Normal Team", "Heroic Team", "Mythic Team", "PvP Team" ].freeze

  has_many :teams, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates_uniqueness_to_tenant :name, case_sensitive: false
  validates :position, presence: true

  scope :ordered, -> { order(:position, :id) }

  before_validation :append_position, on: :create

  # Case-insensitive lookup within the current guild; nil for blank or unknown
  # names — never creates.
  def self.named(name)
    cleaned = name.to_s.strip
    return nil if cleaned.blank?

    where("LOWER(name) = ?", cleaned.downcase).first
  end

  private

  # A blank position on the add form means "at the end".
  def append_position
    self.position = self.class.maximum(:position).to_i + 1 if position.nil?
  end
end
