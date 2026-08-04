# The command manifest — the whole Discord command surface at a glance. Nesting
# `command` builds the tree; a command with children is a subcommand group, a
# command without children is a leaf. Each node's class is discovered from its
# path (e.g. `command :accept` under team/member -> Commands::Team::Member::Accept);
# pass `class:` only to override a non-standard path.
#
# The surface is split by Discord permission tier so each top-level command can
# carry one honest `default_member_permissions`:
#   /team  — single-team, visible to everyone; officer actions gated in-handler.
#   /guild — server-wide administration; Discord hides it from non-managers.

CoBot::CommandRegistry.draw do
  command :team, "Browse and manage a team" do
    command :list
    command :apply
    command :absence
    command :edit

    command :member, "Manage a team member" do
      command :accept
      command :reject
      command :note
      command :remove
    end
  end

  # Server-wide team administration. `permissions: :manage_guild` sets Discord's
  # default_member_permissions so members without Manage Server don't even see
  # the command; each leaf keeps its in-handler admin gate as defense-in-depth.
  command :guild, "Server-wide team administration", permissions: :manage_guild do
    command :create
    command :roster

    # Curated roster lists — teams pick from these; admins manage them here
    # or on the web guild page.
    command :category, "Manage roster categories" do
      command :add
      command :edit
      command :remove
    end

    command :type, "Manage team types" do
      command :add
      command :edit
      command :remove
    end
  end

  # Persistent components (buttons/modals). The custom_id key + params come from
  # each class's `component` declaration.
  component Commands::Components::ApplyModal
  component Commands::Components::ApplyButton
  component Commands::Components::AbsenceModal
  component Commands::Components::Decide
  component Commands::Components::Pause
  component Commands::Components::AddNote
  component Commands::Components::NoteModal
  component Commands::Components::ViewNotes
  # Correcting a character from the DM an applicant gets when it can't be found.
  # These run in a DM, so they resolve their own guild (in_dm: true).
  component Commands::Components::FixCharacter
  component Commands::Components::FixCharacterModal
end
