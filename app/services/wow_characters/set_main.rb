module WowCharacters
  # Decide (or record) which character is a person's main.
  #
  # It arrives three ways, in increasing order of authority:
  #
  #   1. **Implicitly, from the first character they get.** Claim one while
  #      applying and it becomes your main, because with one character there is
  #      no other sensible answer.
  #   2. **Inferred, after a Battle.net link.** Fifty characters arrive at once
  #      and none of them is flagged, so it's a guess — highest level first,
  #      then whoever was played most recently. Only ever fills a blank.
  #   3. **Explicitly.** A person says which one, and nothing overrides it.
  #
  # The distinction that matters: 1 and 2 must never overwrite a choice already
  # made. `ensure` fills a gap; `set` states an intent.
  class SetMain
    def self.ensure(user, now: Time.current) = new(user, now: now).ensure

    def self.set(user, character) = new(user).set(character)

    def initialize(user, now: Time.current)
      @user = user
      @now = now
    end

    # Pick a main only if there isn't one. Also self-heals: a main that was
    # unlinked, released or transferred away leaves a dangling pointer, and the
    # next refresh should quietly choose again rather than showing nothing.
    def ensure
      return @user.main_wow_character if valid_main?

      candidate = best_candidate
      @user.update!(main_wow_character: candidate)
      candidate
    end

    # An explicit choice. Refuses characters that aren't theirs — the main is
    # shown to officers as "this is who I am", so it has to be something they
    # actually own.
    def set(character)
      return false unless character && character.user_id == @user.id

      @user.update!(main_wow_character: character)
      character
    end

    private

    def valid_main?
      main = @user.main_wow_character
      main.present? && main.user_id == @user.id && !main.missing?
    end

    # Highest level, then most recently played. Level is the strong signal —
    # nobody mains a level 20 — and last login breaks ties between the maxed
    # characters, which is where the real answer usually is.
    #
    # `last_login_at` is nil until a refresh has run, so it sorts last rather
    # than beating a character we know was played yesterday.
    def best_candidate
      @user.wow_characters.where(missing_at: nil).max_by do |character|
        [ character.level.to_i, character.last_login_at&.to_i || 0 ]
      end
    end
  end
end
