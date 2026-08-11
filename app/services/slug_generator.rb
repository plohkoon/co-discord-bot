# Derives the human URL slugs the public apply pages use (/apply/:guild_slug).
#
# Base derivation is a plain parameterize (lowercase, hyphens, non-alphanumerics
# stripped); a name that parameterizes to nothing (all-emoji server names are
# real) falls back to the caller's generic base ("guild"/"team"). Collisions are
# resolved by APPENDING A WORD from a small neutral list — "thunder-raiders"
# becomes "thunder-raiders-azure", which stays shareable out loud in a way
# "thunder-raiders-2" doesn't. A numeric suffix is the last resort if the whole
# wordlist is somehow taken.
#
# Pure string logic — the caller supplies `taken` (a callable answering "is
# this slug in use?") so guild slugs check globally and team slugs per guild.
class SlugGenerator
  WORDS = %w[
    amber aurora azure cinder cobalt comet coral crimson dawn drift
    ember ferrous frost gale golden harbor indigo iron ivory jade
    lunar meadow onyx opal pine quartz raven ridge scarlet silver
    sterling summit thunder timber umber violet
  ].freeze

  MAX_LENGTH = 60

  def self.call(name, fallback:, taken:)
    base = derive(name, fallback)
    return base unless taken.call(base)

    WORDS.each do |word|
      candidate = with_suffix(base, "-#{word}")
      return candidate unless taken.call(candidate)
    end

    2.step do |n|
      candidate = with_suffix(base, "-#{n}")
      return candidate unless taken.call(candidate)
    end
  end

  def self.derive(name, fallback)
    slug = name.to_s.parameterize
    slug = slug[0, MAX_LENGTH].to_s.sub(/-+\z/, "")
    slug.presence || fallback
  end

  # Append a suffix without breaking the length cap (trim the base, never the
  # suffix — the suffix is what makes it unique).
  def self.with_suffix(base, suffix)
    head = base[0, MAX_LENGTH - suffix.length].to_s.sub(/-+\z/, "")
    "#{head}#{suffix}"
  end
  private_class_method :with_suffix
end
