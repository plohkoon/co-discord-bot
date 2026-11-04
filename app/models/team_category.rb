# A roster section header ("PvE Teams ⚔️"). Manage Server users curate the
# list on the web guild page; teams pick from it — categories are never
# created on the fly from a team form or command. Ordered by position in the
# directory.
#
# A category can also carry an `about` blurb (Discord markdown), rendered under
# its header, and opt in to `proposals_enabled`: its header then gets an "Apply
# to make a team" button whose submissions (TeamProposal) post to the guild's
# one team-proposals channel. The button shows only while that channel is set
# too — a proposal with nowhere to go would be a dead end.
class TeamCategory < ApplicationRecord
  include GuildScoped

  # Discord's 4000-char text budget is per roster MESSAGE, shared with every
  # team block in it; an about longer than this would crowd them out.
  ABOUT_MAX = 1500

  has_many :teams, dependent: :nullify
  # The FK nullifies too: a proposal outlives the category it was pitched for.
  has_many :team_proposals, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates :about, length: { maximum: ABOUT_MAX }
  validates_uniqueness_to_tenant :name, case_sensitive: false
  validates :position, presence: true

  scope :ordered, -> { order(:position, :id) }

  before_validation :append_position, on: :create
  before_validation :normalize_about

  def accepting_proposals? = proposals_enabled? && guild.team_proposals_enabled?

  # Case-insensitive lookup within the current guild; nil for blank or unknown
  # names — never creates.
  def self.named(name)
    cleaned = name.to_s.strip
    return nil if cleaned.blank?

    where("LOWER(name) = ?", cleaned.downcase).first
  end

  private

  # Blank clears; Windows line endings from a web textarea become plain
  # newlines so the roster's char budget counts what Discord renders.
  def normalize_about
    self.about = about.to_s.gsub("\r\n", "\n").strip.presence
  end

  # A blank position on the add form means "at the end".
  def append_position
    self.position = self.class.maximum(:position).to_i + 1 if position.nil?
  end
end
