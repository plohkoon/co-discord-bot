class NotesCommand < ApplicationCommand
  # 📝 Add note button -> open the note modal
  def new
    membership = find_membership or return
    return respond("Only officers can add notes.") unless officer_for?(membership.team)

    show_modal(title: "Add note — #{membership.discord_username}",
               custom_id: CoBot::Router.custom_id("note_form", membership.id)) do |modal|
      modal.label(label: "Note (officers only)") do |label|
        label.text_input(style: :paragraph, custom_id: "body", required: true,
                         max_length: 2000, placeholder: "Visible only to officers and leads")
      end
    end
  end

  # note modal submit -> save
  def create
    membership = find_membership or return
    return respond("Only officers can add notes.") unless officer_for?(membership.team)

    body = event.value("body").to_s.strip
    return respond("Note was empty.") if body.blank?

    membership.membership_notes.create!(author_discord_id: current_user_id, author_username: author_name, body: body)
    respond("📝 Note added.\n\n#{render_notes(membership)}")
  end

  # 📋 View notes button -> ephemeral list
  def index
    membership = find_membership or return
    return respond("Only officers can view notes.") unless officer_for?(membership.team)

    respond(render_notes(membership))
  end

  private

  def find_membership
    membership = TeamMembership.find_by(id: params[:membership_id])
    respond("That membership no longer exists.") unless membership
    membership
  end

  def author_name
    user = current_user
    user.respond_to?(:username) ? user.username.to_s : user.to_s
  end

  def render_notes(membership)
    notes = membership.membership_notes.limit(20)
    return "*No notes yet for #{membership.discord_username}.*" if notes.empty?

    lines = notes.map { |note| "• #{note.body} — <@#{note.author_discord_id}> · #{note.created_at.strftime('%b %-d')}" }
    "**Notes — #{membership.discord_username}** · #{membership.team.name}\n#{lines.join("\n")}"
  end
end
