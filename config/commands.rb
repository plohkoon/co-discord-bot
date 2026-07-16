# Discord command routes — the single source of truth for slash-command
# registration AND interaction dispatch. Like config/routes.rb, but for Discord.
#
#   command    -> a top-level slash command (optionally with subcommands)
#   subcommand -> "to:" maps to a Command#action (e.g. "teams#create")
#   modal      -> routes a modal submit by custom_id prefix
#   button     -> routes a button press by custom_id prefix
#   as:        -> names the custom_id segments, exposed to the command as params

CoBot::Router.draw do
  command :team, "Manage teams", default_member_permissions: :manage_guild do
    subcommand :create, "Create a team", to: "teams#create" do
      string  :name, "Team name", required: true
      role    :role, "Role granted to team members", required: true
      role    :officer_role, "Role pinged to review applications", required: true
      channel :review_channel, "Channel where applications are posted", required: true, channel_types: [ :text ]
    end
    subcommand :list, "List this server's teams", to: "teams#index"
  end

  command :apply, "Apply to join a team", to: "apply#new" do
    string :team, "The team you want to apply to", required: true, autocomplete: true
  end

  # Persistent components — survive restarts because Discord keeps the message +
  # custom_id and we re-attach these handlers on boot.
  modal  :apply,  to: "apply#create", as: [ :team_id ]
  button :decide, to: "apply#decide", as: [ :decision, :application_id ]
end
