# A character knows a recipe. Deliberately just two ids.
class WowCharacterRecipe < ApplicationRecord
  belongs_to :wow_character
  belongs_to :wow_recipe, foreign_key: :recipe_id, primary_key: :recipe_id,
                          inverse_of: :wow_character_recipes, optional: true

  validates :recipe_id, presence: true, uniqueness: { scope: :wow_character_id }

  # How much of the population this data can actually speak for.
  #
  # Any answer built on recipes is bounded by who has linked Battle.net: "nobody
  # knows it" and "the person who knows it never linked" look identical from
  # here. Surfacing this next to a result is the difference between a useful
  # answer and a quietly misleading one.
  Coverage = Struct.new(:linked_characters, :linked_users, keyword_init: true)

  def self.coverage
    Coverage.new(
      linked_characters: WowCharacter.joins(:wow_character_recipes).distinct.count,
      linked_users: User.joins(battle_net_accounts: :wow_characters).distinct.count
    )
  end
end
