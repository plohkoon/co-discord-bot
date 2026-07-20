require "test_helper"

module Absences
  class DateParserTest < ActiveSupport::TestCase
    # A fixed "now" in a non-UTC zone so "today"/weekday/horizon math is
    # deterministic and we exercise the guild-tz interpretation.
    ZONE = ActiveSupport::TimeZone["America/New_York"]

    def parse(input) = DateParser.call(input, time_zone: ZONE)

    # 2026-07-20 is a Monday.
    def around(&block) = travel_to(Time.utc(2026, 7, 20, 15, 0, 0), &block)

    test "parses ISO YYYY-MM-DD" do
      around { assert_equal Date.new(2026, 7, 26), parse("2026-07-26") }
    end

    test "parses today and tomorrow in the guild time zone" do
      around do
        assert_equal Date.new(2026, 7, 20), parse("today")
        assert_equal Date.new(2026, 7, 21), parse("tomorrow")
      end
    end

    test "parses a bare weekday name as the next occurrence (today counts)" do
      around do
        assert_equal Date.new(2026, 7, 25), parse("Saturday") # next Saturday
        assert_equal Date.new(2026, 7, 25), parse("sat")
        assert_equal Date.new(2026, 7, 20), parse("Monday")   # today is Monday
      end
    end

    test "parses a Mon D date in the current year" do
      around do
        assert_equal Date.new(2026, 7, 26), parse("Jul 26")
        assert_equal Date.new(2026, 8, 1),  parse("August 1")
      end
    end

    test "a Mon D whose month already passed rolls into next year (within the horizon)" do
      travel_to(Time.utc(2026, 12, 20, 15, 0, 0)) do
        assert_equal Date.new(2027, 1, 5), parse("Jan 5") # past this year -> next year, ~16 days out
      end
    end

    test "rejects garbage, past dates, and dates beyond the 60-day horizon" do
      around do
        assert_raises(DateParser::Invalid) { parse("someday") }
        assert_raises(DateParser::Invalid) { parse("") }
        assert_raises(DateParser::Invalid) { parse("2026-07-19") } # yesterday
        assert_raises(DateParser::Invalid) { parse("2026-13-40") } # impossible
        assert_raises(DateParser::Invalid) { parse("2026-12-31") } # beyond horizon
      end
    end

    test "the horizon is measured in the guild time zone" do
      around do
        assert_equal Date.new(2026, 9, 18), parse("2026-09-18") # exactly 60 days out is allowed
        assert_raises(DateParser::Invalid) { parse("2026-09-19") } # 61 days out
      end
    end
  end
end
