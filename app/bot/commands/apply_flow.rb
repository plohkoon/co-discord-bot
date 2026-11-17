module Commands
  # Shared by /team apply and the roster Apply button: membership pre-checks +
  # the question modal. Submission lands in Components::ApplyModal either way.
  module ApplyFlow
    def start_application(team)
      # Closed to applications: the roster button is hidden, but /team apply and
      # any stale/persistent button still reach here — refuse with the notice.
      return respond(team.resolved_closed_message) unless team.recruiting?
      return respond("You're already a member of **#{team.name}**.") if member_of?(team)
      return respond("You already have a pending application to **#{team.name}**.") if pending_for?(team)

      questions = team.application_questions.ordered.to_a
      collect_character = team.collect_character?
      if questions.empty? && !collect_character
        return respond("**#{team.name}** has no application questions set up yet.")
      end

      show_modal(title: "Apply — #{team.name}", custom_id: CoBot::CommandRegistry.custom_id("apply", team.id)) do |modal|
        # First slot, because it's the one field the bot acts on rather than
        # just files. Costs one of Discord's five, which is why Team#question_limit
        # drops to four when this is on.
        if collect_character
          game = team.wow_game
          modal.label(label: game.character_label) do |label|
            label.text_input(style: :short, custom_id: "character", required: false,
                             max_length: 64, placeholder: game.character_placeholder)
          end
        end

        questions.each do |question|
          modal.label(label: question.label, description: question.description.presence) do |label|
            question_input(label, question)
          end
        end
      end
    end

    private

    # One Label child per question style. Options are passed as plain
    # value/label hashes (the label doubles as the value) rather than through
    # discordrb's builder, which would send `description: null, default: null`
    # on every option.
    def question_input(label, question)
      custom_id = "q:#{question.id}"
      options = question.options.map { |option| { value: option, label: option } }

      case question.style
      when "choice"
        label.radio_group(custom_id: custom_id, buttons: options, required: question.required)
      when "checkboxes"
        # Discord defaults min_values to 1; an optional group must allow 0.
        label.checkbox_group(custom_id: custom_id, checkboxes: options, required: question.required,
                             min_values: (0 unless question.required))
      when "yes_no"
        label.checkbox(custom_id: custom_id)
      else
        label.text_input(
          style: question.paragraph? ? :paragraph : :short,
          custom_id: custom_id,
          required: question.required,
          min_length: question.min_length,
          max_length: question.max_length,
          placeholder: question.placeholder.presence
        )
      end
    end

    def member_of?(team)   = team.team_memberships.active.where(discord_user_id: current_user_id).exists?
    def pending_for?(team) = team.team_memberships.pending.where(discord_user_id: current_user_id).exists?
  end
end
