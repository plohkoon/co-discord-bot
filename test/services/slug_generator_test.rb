require "test_helper"

class SlugGeneratorTest < ActiveSupport::TestCase
  def generate(name, taken: [], fallback: "guild")
    taken_set = taken.to_set
    SlugGenerator.call(name, fallback: fallback, taken: ->(candidate) { taken_set.include?(candidate) })
  end

  test "derives a parameterized slug from the name" do
    assert_equal "thunder-raiders", generate("Thunder Raiders")
    assert_equal "the-a-team", generate("The A-Team!")
    assert_equal "cafe-crew", generate("Café Crew")
  end

  test "a name that parameterizes to nothing falls back to the generic base" do
    assert_equal "guild", generate("🔥🔥🔥")
    assert_equal "team", generate("!!!", fallback: "team")
  end

  test "a collision appends a word, not a number" do
    slug = generate("Thunder Raiders", taken: [ "thunder-raiders" ])

    assert_match(/\Athunder-raiders-[a-z]+\z/, slug)
    assert_no_match(/\d/, slug)
    assert_includes SlugGenerator::WORDS, slug.split("-").last
  end

  test "further collisions walk the wordlist" do
    first_two = SlugGenerator::WORDS.first(2).map { |w| "thunder-raiders-#{w}" }
    slug = generate("Thunder Raiders", taken: [ "thunder-raiders" ] + first_two)

    assert_equal "thunder-raiders-#{SlugGenerator::WORDS[2]}", slug
  end

  test "an exhausted wordlist falls back to a numeric suffix" do
    taken = [ "guild" ] + SlugGenerator::WORDS.map { |w| "guild-#{w}" }

    assert_equal "guild-2", generate("🔥", taken: taken)
    assert_equal "guild-3", generate("🔥", taken: taken + [ "guild-2" ])
  end

  test "long names are trimmed to the cap, suffix included" do
    long = "a" * 100
    slug = generate(long)
    assert slug.length <= SlugGenerator::MAX_LENGTH

    with_suffix = generate(long, taken: [ slug ])
    assert with_suffix.length <= SlugGenerator::MAX_LENGTH
    assert_includes SlugGenerator::WORDS, with_suffix.split("-").last
  end
end
