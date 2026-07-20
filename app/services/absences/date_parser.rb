module Absences
  # Parses free-typed call-out text into a Date, interpreted in the guild's time
  # zone. Accepts ISO YYYY-MM-DD (canonical), `today`/`tomorrow`, bare weekday
  # names (the next occurrence, today included), and "Mon D" (e.g. "Jul 26").
  # Rejects unparseable input, days already past, and days beyond a 60-day
  # horizon — all as DateParser::Invalid carrying a friendly accepted-formats
  # message. Parsing is kept out of the modal component so the rules live in one
  # testable place.
  class DateParser
    class Invalid < StandardError; end

    HORIZON_DAYS = 60
    ACCEPTED = "Try a date like `2026-07-26`, `today`, `tomorrow`, a weekday (e.g. `Saturday`), or `Jul 26`.".freeze

    WEEKDAYS = (Date::DAYNAMES + Date::ABBR_DAYNAMES)
               .each_with_index.to_h { |name, i| [ name.downcase, i % 7 ] }.freeze
    MONTHS = (Date::MONTHNAMES + Date::ABBR_MONTHNAMES)
             .each_with_index.filter_map { |name, i| [ name.downcase, i % 13 ] if name }.to_h.freeze

    def self.call(...) = new(...).call

    def initialize(input, time_zone:)
      @input = input.to_s.strip
      @zone = time_zone
    end

    def call
      raise Invalid, "Tell me which day you'll miss. #{ACCEPTED}" if @input.blank?

      date = parse or raise Invalid, %(I couldn't read "#{@input}" as a date. #{ACCEPTED})

      today = @zone.today
      raise Invalid, "That day is already past. #{ACCEPTED}" if date < today
      raise Invalid, "That's more than #{HORIZON_DAYS} days out — call out closer to the day." if date > today + HORIZON_DAYS

      date
    end

    private

    def parse
      normalized = @input.downcase
      return @zone.today       if normalized == "today"
      return @zone.today + 1   if normalized == "tomorrow"

      iso_date(normalized) || weekday_date(normalized) || month_day_date(normalized)
    end

    def iso_date(text)
      match = text.match(/\A(\d{4})-(\d{1,2})-(\d{1,2})\z/) or return
      build_date(match[1].to_i, match[2].to_i, match[3].to_i)
    end

    def weekday_date(text)
      wday = WEEKDAYS[text] or return

      today = @zone.today
      today + ((wday - today.wday) % 7)
    end

    def month_day_date(text)
      match = text.match(/\A([a-z]+)\.?\s+(\d{1,2})\z/) or return
      month = MONTHS[match[1]] or return

      today = @zone.today
      date = build_date(today.year, month, match[2].to_i) or return
      # A month/day already gone this year means they mean next year.
      date < today ? build_date(today.year + 1, month, match[2].to_i) : date
    end

    def build_date(year, month, day)
      Date.new(year, month, day)
    rescue Date::Error
      nil
    end
  end
end
