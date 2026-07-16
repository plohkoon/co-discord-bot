module MessageActions
  # One class per automatic message action; the manifest (config/message_actions.rb)
  # lists which are live. Declare what to match and what to do:
  #
  #   class MessageActions::MeatReact < MessageActions::Base
  #     match word: "meat"
  #     def perform = react("🥩")
  #   end
  #
  # Matchers (exactly one per class): `word:` (case-insensitive, word-boundary),
  # `contains:` (case-insensitive substring), `pattern:` (raw Regexp).
  #
  # `perform` runs inside the guild tenant and the Rails executor, but on the
  # gateway thread — keep it fast and never open long transactions here.
  class Base
    class << self
      attr_reader :matcher

      def match(word: nil, contains: nil, pattern: nil)
        given = { word: word, contains: contains, pattern: pattern }.compact
        raise ArgumentError, "match takes exactly one of word:/contains:/pattern: (got #{given.keys.inspect})" unless given.size == 1

        @matcher =
          case given.each_key.first
          when :word     then /\b#{Regexp.escape(word)}\b/i
          when :contains then /#{Regexp.escape(contains)}/i
          when :pattern  then pattern
          end
      end

      def matches?(content)
        raise "#{name} declares no `match`" unless matcher

        matcher.match?(content.to_s)
      end
    end

    attr_reader :event, :guild

    def initialize(event:, guild:)
      @event = event
      @guild = guild
    end

    def perform = raise NotImplementedError, "#{self.class.name} must define #perform"

    private

    def message = event.message

    def react(emoji) = message.react(emoji)
  end
end
