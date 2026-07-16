module Commands
  # Base for every slash command and component handler. Subclasses declare their
  # options + autocomplete + handler in one place (the class), and the namespace
  # is the Discord command path: Commands::Team::Member::Accept -> /team member accept.
  class Base
    Option = Struct.new(:type, :name, :description, :required, :autocomplete, :channel_types, keyword_init: true)

    class << self
      def description(text = nil)
        text ? @description = text : @description
      end

      # option DSL: string :name, "desc", required:, autocomplete:, channel_types:
      %i[string integer boolean user role channel mentionable].each do |type|
        define_method(type) do |name, description, required: false, autocomplete: false, channel_types: nil|
          command_options << Option.new(type: type, name: name.to_s, description: description,
                                        required: required, autocomplete: autocomplete, channel_types: channel_types)
        end
      end

      def command_options
        @command_options ||= []
      end

      # permission gating (enforced in-handler — Discord's default_member_permissions
      # is per-command, but our actions live under one /team command with mixed access)
      def requires(role = :__read__)
        role == :__read__ ? @requires : (@requires = role)
      end
      def admin_only! = requires(:admin)
      def officer_only! = requires(:officer)

      # component handlers declare a custom_id key + params
      def component(kind, key, params: [])
        @component_spec = { kind: kind.to_sym, key: key.to_s, params: Array(params).map(&:to_sym) }
      end
      def component_spec = @component_spec
    end

    attr_reader :event, :guild, :params

    def initialize(event:, guild:, params: {})
      @event = event
      @guild = guild
      @params = params || {}
      @performed = false
    end

    def process(action = :call)
      return unless authorized?

      public_send(action)
    end

    # Autocomplete entry: dispatch to autocomplete_<option>(query).
    def autocomplete(option_name)
      method = "autocomplete_#{option_name}"
      choices = respond_to?(method, true) ? send(method, option(option_name).to_s) : {}
      event.respond(choices: choices || {})
    end

    private

    def authorized?
      case self.class.requires
      when :admin
        return true if admin?

        respond("⛔ You need the **Manage Server** permission to do that.")
        false
      when :officer
        team = authorization_team
        return true if team && officer_for?(team)

        respond("⛔ Only #{team&.name || 'team'} officers can do that.")
        false
      else
        true
      end
    end

    # Officer commands resolve their team from the :team option by default.
    def authorization_team
      resolve_team(option(:team)) if option(:team)
    end

    # --- context / options ---
    def option(name) = event.options[name.to_s]
    def current_user = event.user
    def current_user_id = event.user&.id
    def current_guild = guild
    def server = event.server

    def admin?
      member = current_user
      member.respond_to?(:permission?) && (member.permission?(:administrator) || member.permission?(:manage_server))
    end

    def officer_for?(team)
      member = current_user
      return false unless member.respond_to?(:roles)

      member.permission?(:administrator) || member.permission?(:manage_server) ||
        member.roles.any? { |role| role.id == team.officer_role_id }
    end

    def resolve_team(raw)
      raw = raw.to_s
      scope = current_guild.teams.active
      raw.match?(/\A\d+\z/) ? scope.find_by(id: raw) : scope.matching(raw).first
    end

    # --- responses (each is one interaction ack) ---
    def respond(content = nil, ephemeral: true, embeds: nil, components: nil)
      ack!
      event.respond(content: content, ephemeral: ephemeral, embeds: Array(embeds).compact.presence, components: components)
    end

    def show_modal(title:, custom_id:, &block)
      ack!
      event.show_modal(title: title.to_s[0, 45], custom_id: custom_id, &block)
    end

    def update_message(content: nil, embeds: nil, components: [])
      ack!
      event.update_message(content: content, embeds: Array(embeds).compact.presence, components: components)
    end

    # Follow-up message AFTER the single ack (Discord allows them for 15
    # minutes) — for reporting on slow work done post-response, e.g. member
    # backfill that has to chunk the server's member list.
    def follow_up(content, ephemeral: true)
      event.interaction.send_message(content: content, ephemeral: ephemeral)
    end

    def ack!
      raise "this interaction has already been answered" if @performed

      @performed = true
    end

    # --- shared note rendering (used by note components) ---
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
end
