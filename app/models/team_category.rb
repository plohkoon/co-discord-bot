# A roster section header ("PvE Teams ⚔️"). Created on the fly the first time
# a team names it; ordered by position (creation order) in the directory.
class TeamCategory < ApplicationRecord
  include GuildScoped

  has_many :teams, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates_uniqueness_to_tenant :name, case_sensitive: false

  scope :ordered, -> { order(:position, :id) }

  def self.locate(name)
    cleaned = name.to_s.strip
    return nil if cleaned.blank?

    where("LOWER(name) = ?", cleaned.downcase).first ||
      create!(name: cleaned, position: maximum(:position).to_i + 1)
  end
end
