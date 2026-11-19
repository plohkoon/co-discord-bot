module Teams
  # Every member of a team (any status) with the character they play on it, as
  # CSV. One row per person, where the applications export is one row per
  # application.
  #
  # The character falls back to what they last applied on, the same fallback
  # the membership page uses: a lead exporting a fresh roster shouldn't get a
  # blank column just because nobody has set "active character" yet.
  class MembersReport
    STATUS_ORDER = %w[active pending archived].freeze

    HEADERS = [ "Member", "Discord ID", "Status", "Joined at", "Left at",
                "Character", "Character class", "Character spec", "Character role", "Item level", "M+ score", "Raid progress",
                "Applications", "Last applied at", "Last application status" ].freeze

    attr_reader :team

    def initialize(team)
      @team = team
    end

    def memberships
      @memberships ||= team.team_memberships
                           .includes(:wow_character, team_applications: :wow_character)
                           .sort_by { |m| [ STATUS_ORDER.index(m.status) || STATUS_ORDER.size, m.discord_username.to_s.downcase ] }
    end

    def to_csv
      rows = memberships.map do |membership|
        applications = membership.team_applications.sort_by(&:created_at).reverse
        latest = applications.first
        character = membership.wow_character || applications.detect(&:wow_character)&.wow_character
        [
          membership.discord_username.presence,
          membership.discord_user_id.to_s,
          membership.status,
          CsvExport.timestamp(membership.joined_at),
          CsvExport.timestamp(membership.left_at),
          character&.full_name || latest&.character_input.presence,
          character&.playable_class,
          character&.active_spec,
          character&.role,
          character&.ilvl,
          character&.mythic_score,
          character&.raid_progress_headline,
          applications.size,
          CsvExport.timestamp(latest&.created_at),
          latest&.status
        ]
      end
      CsvExport.generate(HEADERS, rows)
    end
  end
end
