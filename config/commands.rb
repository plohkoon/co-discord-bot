# The command manifest — the whole Discord command surface at a glance. Each
# node points at a class in app/bot/commands that owns its options, autocomplete,
# and handler. Like config/routes.rb, but for Discord interactions.

CoBot::CommandRegistry.draw do
  command :team, "Manage teams" do
    subcommand :create, Commands::Team::Create
    subcommand :list,   Commands::Team::List
    subcommand :apply,  Commands::Team::Apply

    group :member, "Manage a team member" do
      subcommand :accept, Commands::Team::Member::Accept
      subcommand :reject, Commands::Team::Member::Reject
      subcommand :note,   Commands::Team::Member::Note
      subcommand :remove, Commands::Team::Member::Remove
    end
  end

  # Persistent components (buttons/modals). The custom_id key + params come from
  # each class's `component` declaration.
  component Commands::Components::ApplyModal
  component Commands::Components::Decide
  component Commands::Components::AddNote
  component Commands::Components::NoteModal
  component Commands::Components::ViewNotes
end
