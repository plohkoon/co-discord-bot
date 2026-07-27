module Applications
  # The one-line-per-fact digest of an applicant's character, for the officer
  # review message.
  #
  # Its real job is being honest about **which of four states** an application
  # is in, because three of them look like "no data" if you're careless:
  #
  #   :not_asked  the team doesn't collect a character — show nothing at all
  #   :loading    they named one and we haven't finished looking it up
  #   :failed     they named one Blizzard doesn't recognise (a typo, usually)
  #   :ready      we have it
  #
  # `:loading` and `:failed` must never render as an empty summary. An officer
  # reading "no parses" about someone who has a 99 would be worse than showing
  # nothing, so each state says what it is.
  class RaiderSummary
    Result = Struct.new(:state, :character, :lines, keyword_init: true) do
      def ready? = state == :ready
      def show? = state != :not_asked
    end

    HEADING = "Raider data".freeze

    def self.call(application) = new(application).call

    def initialize(application)
      @application = application
    end

    def call
      return result(:not_asked) unless @application.character_asked?
      # Order matters: "haven't looked yet" has to win over "found nothing",
      # or every application reads as a typo for its first few seconds.
      return result(:loading) if @application.character_pending?
      return result(:failed) if @application.character_unresolved?

      character = @application.wow_character
      return result(:loading) if character.nil? || !gathered?(character)

      result(:ready, character: character, lines: lines_for(character))
    end

    # What Discord shows in the embed field, or the web page shows inline.
    def self.body(application)
      summary = call(application)
      case summary.state
      when :not_asked then nil
      when :loading   then "⏳ Loading raider data…"
      when :failed    then "⚠️ Cannot load raider data — no character called " \
                           "**#{application.character_input}**."
      else summary.lines.join("\n")
      end
    end

    private

    # A character row exists from the moment it's claimed, before any of the
    # four services have been asked. Treat "claimed but never refreshed" as
    # still loading rather than as a character with nothing to its name.
    def gathered?(character) = character.refreshed_at.present?

    def result(state, character: nil, lines: [])
      Result.new(state: state, character: character, lines: lines)
    end

    # Deliberately short: the review message is a decision aid, not a dossier.
    # The web page carries the full history.
    def lines_for(character)
      [
        identity_line(character),
        parse_line(character),
        mythic_line(character),
        raid_line(character),
        credential_line(character)
      ].compact
    end

    def identity_line(character)
      bits = [ character.full_name,
               character.spec_and_class || character.playable_class,
               character.ilvl && "ilvl #{character.ilvl}" ].compact.join(" · ")
      # An unverified character is a claim, not a fact, and an officer weighing
      # an applicant should know which they're reading.
      bits += character.verified? ? "" : "  *(unverified)*"
      bits
    end

    def parse_line(character)
      ranking = character.best_ranking or return nil

      "**Parse** #{ranking.summary} — #{ranking.zone_name}"
    end

    def mythic_line(character)
      score = character.mythic_score or return nil

      peak = character.peak_score
      line = "**M+** #{score}"
      # Peak only earns its space when it says something the current score
      # doesn't — a fallen-off raider reads very differently from a rising one.
      line += " (peak #{peak})" if peak && peak > score
      line += " · #{character.role.upcase}" if character.role
      line
    end

    def raid_line(character)
      progress = character.raid_progress_headline or return nil

      "**Raid** #{progress}"
    end

    # Cutting Edge and AOTC are the credentials people actually ask about, and
    # the date is the claim — "CE in 2024" differs from "CE eventually".
    def credential_line(character)
      credential = character.best_raid_credential or return nil

      "**Best** #{credential.summary}"
    end
  end
end
