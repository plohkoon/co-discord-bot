# The WoW game a team plays. Retail and WoW: Forever are separate games —
# separate characters, realms and Blizzard API namespaces — so anything that
# turns an applicant's typed character into data has to know which one it's in.
#
# This is the one place a game's differences live. Today that's only how the
# character is asked for and whether co-bot can look it up at all: Forever
# launched (2026-11-04) before Blizzard published an API namespace for it, and
# its characters carry two-part names (first + surname, unique per region on a
# per-ruleset mega-realm), which Name-Realm resolution can't express. So a
# Forever team still collects the character — verbatim, for officers to read —
# but nothing tries to resolve it. When the API lands, the namespace, level cap
# and refresh steps belong here too (issue #48).
WowGame = Data.define(:key, :name, :character_label, :character_placeholder, :lookup) do
  def lookup? = lookup
end

class WowGame
  RETAIL = new(key: "retail", name: "World of Warcraft (Retail)",
               character_label: "Your character (Name-Realm)",
               character_placeholder: "Thrall-Sargeras",
               lookup: true)
  FOREVER = new(key: "forever", name: "WoW: Forever",
                character_label: "Your character (first and last name)",
                character_placeholder: "e.g. Tarren Mistwalker",
                lookup: false)

  ALL = [ RETAIL, FOREVER ].index_by(&:key).freeze

  def self.fetch(key) = ALL.fetch(key.to_s, RETAIL)

  # [label, key] pairs for a select box or Discord option choices.
  def self.choices = ALL.values.map { |game| [ game.name, game.key ] }
end
