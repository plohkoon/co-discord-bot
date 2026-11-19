module Teams
  # Every application on a team as one table — a column per question — so a
  # lead can scan what everyone answered (class, availability, …) without
  # opening each member. Backs both the web page and its CSV export, so the two
  # can't disagree about what a column means.
  #
  # Columns are keyed on `question_key`, not the label: a reworded question is
  # still the same question, and its answers belong in one column. Current
  # questions come first in their configured order, titled with today's label;
  # questions since deleted follow, titled with the label they were last
  # answered under — their answers are still on record and still worth seeing.
  class ApplicationsReport
    Column = Data.define(:key, :label)

    STATUSES = TeamApplication.statuses.keys.freeze

    attr_reader :team, :status

    def initialize(team, status: nil)
      @team = team
      @status = status.presence_in(STATUSES)
    end

    def applications
      @applications ||= begin
        scope = team.team_applications.includes(:application_answers, :team_membership, :wow_character).recent
        scope = scope.where(status: status) if status
        scope.to_a
      end
    end

    def columns
      @columns ||= begin
        current = team.application_questions.ordered.map { |q| Column.new(key: q.key, label: q.label) }
        known = current.map(&:key).to_set
        # `applications` is newest first, so the first label seen per retired
        # key is the one it was most recently asked as.
        retired = applications.flat_map(&:application_answers).each_with_object({}) do |answer, acc|
          next if known.include?(answer.question_key)

          acc[answer.question_key] ||= answer.question_label
        end
        current + retired.map { |key, label| Column.new(key: key, label: label) }
      end
    end

    # Answers for one application, aligned to `columns`. A question added after
    # they applied is nil (never asked), distinct from "" (asked, left blank).
    def answers_for(application)
      by_key = application.application_answers.index_by(&:question_key)
      columns.map { |column| by_key[column.key]&.answer }
    end

    # What they applied as: the resolved character when there is one, otherwise
    # exactly what they typed — an unresolved name is still the applicant's
    # stated intent, and often enough for a lead to know who they are.
    def self.character_label(application)
      application.wow_character&.full_name || application.character_input.presence
    end

    HEADERS = [ "Applicant", "Discord ID", "Applied at", "Status", "Decided at", "Source",
                "Character", "Character class", "Character spec", "Character role", "Item level", "M+ score" ].freeze

    def to_csv
      rows = applications.map do |app|
        character = app.wow_character
        [
          app.discord_username.presence || app.team_membership&.discord_username,
          app.discord_user_id.to_s,
          CsvExport.timestamp(app.created_at),
          app.status,
          CsvExport.timestamp(app.decided_at),
          app.source,
          self.class.character_label(app),
          character&.playable_class,
          character&.active_spec,
          character&.role,
          character&.ilvl,
          character&.mythic_score,
          *answers_for(app)
        ]
      end
      CsvExport.generate(HEADERS + columns.map(&:label), rows)
    end
  end
end
