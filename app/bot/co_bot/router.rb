module CoBot
  # A Rails-routes-style DSL for Discord interactions. The single source of
  # truth: it BOTH generates the slash-command registration payload AND drives
  # dispatch to CommandControllers. Draw routes in config/discord_routes.rb.
  class Router
    Option     = Struct.new(:type, :name, :description, :required, :autocomplete, :channel_types, keyword_init: true)
    Subcommand = Struct.new(:name, :description, :action, :options, keyword_init: true)
    Command    = Struct.new(:name, :description, :default_member_permissions, :action, :options, :subcommands, keyword_init: true)
    Component  = Struct.new(:kind, :key, :action, :param_names, keyword_init: true)

    # Discord permission bitfields (passed to the API as a STRING).
    PERMISSION_BITS = {
      administrator:   1 << 3,
      manage_channels: 1 << 4,
      manage_guild:    1 << 5,
      manage_roles:    1 << 28
    }.freeze

    class << self
      def draw(&block)
        @definition = Definition.new
        @definition.instance_eval(&block)
        @definition
      end

      def definition
        @definition ||= load_routes
      end

      def reload!
        @definition = nil
        definition
      end

      def load_routes
        @definition = nil
        Kernel.load(Rails.root.join("config/commands.rb").to_s)
        @definition
      end

      # Build a component custom_id: "key:val1:val2".
      def custom_id(key, *values)
        [ key, *values ].join(":")
      end

      # (Re)register every command for one guild. Guild-scoped commands
      # propagate instantly. register_application_command upserts, so this is
      # safe to call on every (re)connect.
      def register(bot, guild_id)
        definition.commands.each do |cmd|
          bot.register_application_command(
            cmd.name, cmd.description,
            server_id: guild_id,
            default_member_permissions: permission_bitfield(cmd.default_member_permissions)
          ) do |builder|
            apply_options(builder, cmd.options)
            cmd.subcommands.each do |sub|
              builder.subcommand(sub.name, sub.description) do |sub_builder|
                apply_options(sub_builder, sub.options)
              end
            end
          end
        end
      end

      def permission_bitfield(sym)
        return nil if sym.nil?

        PERMISSION_BITS.fetch(sym).to_s
      end

      def apply_options(builder, options)
        options.each do |opt|
          case opt.type
          when :string      then builder.string(opt.name, opt.description, required: opt.required, autocomplete: opt.autocomplete)
          when :integer     then builder.integer(opt.name, opt.description, required: opt.required)
          when :boolean     then builder.boolean(opt.name, opt.description, required: opt.required)
          when :user        then builder.user(opt.name, opt.description, required: opt.required)
          when :role        then builder.role(opt.name, opt.description, required: opt.required)
          when :channel     then builder.channel(opt.name, opt.description, required: opt.required, types: opt.channel_types)
          when :mentionable then builder.mentionable(opt.name, opt.description, required: opt.required)
          end
        end
      end
    end

    # --- the DSL surface (instance_eval'd inside Router.draw) ---
    class Definition
      attr_reader :commands, :components

      def initialize
        @commands = []
        @components = []
      end

      def command(name, description, default_member_permissions: nil, to: nil, &block)
        cmd = Command.new(name: name, description: description,
                          default_member_permissions: default_member_permissions,
                          action: to, options: [], subcommands: [])
        CommandBuilder.new(cmd).instance_eval(&block) if block
        @commands << cmd
      end

      def modal(key, to:, as: [])
        @components << Component.new(kind: :modal, key: key.to_s, action: to, param_names: Array(as))
      end

      def button(key, to:, as: [])
        @components << Component.new(kind: :button, key: key.to_s, action: to, param_names: Array(as))
      end
    end

    # Shared option declarations (string/role/channel/…) for commands and subcommands.
    module OptionMethods
      %i[string integer boolean user role channel mentionable].each do |type|
        define_method(type) do |name, description, required: false, autocomplete: false, channel_types: nil|
          option_target << Option.new(type: type, name: name, description: description,
                                      required: required, autocomplete: autocomplete,
                                      channel_types: channel_types)
        end
      end
    end

    class CommandBuilder
      include OptionMethods

      def initialize(command) = @command = command
      def option_target = @command.options

      def subcommand(name, description, to:, &block)
        sub = Subcommand.new(name: name, description: description, action: to, options: [])
        SubcommandBuilder.new(sub).instance_eval(&block) if block
        @command.subcommands << sub
      end
    end

    class SubcommandBuilder
      include OptionMethods

      def initialize(subcommand) = @subcommand = subcommand
      def option_target = @subcommand.options
    end
  end
end
