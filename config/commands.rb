# The command manifest — the whole Discord command surface at a glance. Nesting
# `command` builds the tree; a command with children is a subcommand group, a
# command without children is a leaf. Each node's class is discovered from its
# path (e.g. `command :accept` under team/member -> Commands::Team::Member::Accept);
# pass `class:` only to override a non-standard path.

CoBot::CommandRegistry.draw do
  command :team, "Manage teams" do
    command :create
    command :list
    command :apply
    command :edit
    command :roster

    command :member, "Manage a team member" do
      command :accept
      command :reject
      command :note
      command :remove
    end
  end

  # Persistent components (buttons/modals). The custom_id key + params come from
  # each class's `component` declaration.
  component Commands::Components::ApplyModal
  component Commands::Components::ApplyButton
  component Commands::Components::Decide
  component Commands::Components::AddNote
  component Commands::Components::NoteModal
  component Commands::Components::ViewNotes
end
