# One craftable recipe, from Blizzard's static profession data.
#
# The catalog exists so a search can distinguish "nobody knows this" from
# "that isn't a recipe" — only the first answers whether it's worth finding a
# crafter. It also carries Blizzard's own categories, which the per-character
# payload doesn't include.
class WowRecipe < ApplicationRecord
  has_many :wow_character_recipes, foreign_key: :recipe_id, primary_key: :recipe_id,
                                   inverse_of: :wow_recipe, dependent: nil

  validates :recipe_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :for_profession, ->(name) { where(profession_name: name) }
  scope :in_tier, ->(tier_id) { where(skill_tier_id: tier_id) }
  scope :by_name, -> { order(:name) }
  # Case-insensitive contains. SQLite's LIKE is already case-insensitive for
  # ASCII; lowering both sides keeps it right for accented names too.
  scope :matching, lambda { |query|
    q = query.to_s.strip
    q.present? ? where("LOWER(name) LIKE ?", "%#{q.downcase}%") : none
  }

  # The characters known to have learned it. "Known to" is doing real work: this
  # can only ever cover characters belonging to people who linked Battle.net,
  # so callers showing this to a human must show the coverage alongside it (see
  # WowCharacterRecipe.coverage).
  def known_by
    WowCharacter.joins(:wow_character_recipes)
                .where(wow_character_recipes: { recipe_id: recipe_id })
                .by_prominence
  end

  def known_by_count = wow_character_recipes.count

  def summary = [ name, category.presence, skill_tier_name.presence ].compact.join(" · ")
end
