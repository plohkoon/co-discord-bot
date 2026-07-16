module CoBot
  # The command manifest (config/commands.rb) wires the Discord command tree to
  # command classes — like config/routes.rb, but pointing at classes instead of
  # methods. The classes own their options/autocomplete/handler; this owns the
  # structure. Loading the manifest connects everything.
  module CommandRegistry
    Group   = Struct.new(:name, :description, :subcommands, keyword_init: true)
    Command = Struct.new(:name, :description, :standalone, :subcommands, :groups, keyword_init: true)

    class << self
      # --- manifest DSL ---
      def draw(&block)
        @definition = Definition.new
        @definition.instance_eval(&block)
        @definition
      end

      def definition
        @definition ||= load_manifest
      end

      def reload!
        @definition = nil
        definition
      end

      def custom_id(key, *values) = [ key, *values ].join(":")

      def components = definition.components

      # path (array of symbols) -> command class
      def dispatch_table
        table = {}
        definition.commands.each do |cmd|
          if cmd.standalone
            table[[ cmd.name ]] = cmd.standalone
          else
            cmd.subcommands.each { |name, klass| table[[ cmd.name, name ]] = klass }
            cmd.groups.each_value do |grp|
              grp.subcommands.each { |name, klass| table[[ cmd.name, grp.name, name ]] = klass }
            end
          end
        end
        table
      end

      def command_for(command_name:, subcommand_group: nil, subcommand: nil)
        path = [ command_name, subcommand_group, subcommand ].compact.map(&:to_sym)
        dispatch_table[path]
      end

      # (Re)register every command for one guild. register_application_command upserts.
      def register(bot, guild_id)
        definition.commands.each do |cmd|
          bot.register_application_command(cmd.name, cmd.description, server_id: guild_id) do |builder|
            if cmd.standalone
              apply_options(builder, cmd.standalone.command_options)
            else
              cmd.subcommands.each do |name, klass|
                builder.subcommand(name, klass.description || name.to_s) { |sc| apply_options(sc, klass.command_options) }
              end
              cmd.groups.each_value do |grp|
                builder.subcommand_group(grp.name, grp.description) do |group|
                  grp.subcommands.each { |name, klass| group.subcommand(name, klass.description || name.to_s) { |sc| apply_options(sc, klass.command_options) } }
                end
              end
            end
          end
        end
      end

      private

      def load_manifest
        @definition = nil
        Kernel.load(Rails.root.join("config/commands.rb").to_s)
        @definition
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

    # --- the DSL surface (instance_eval'd inside .draw) ---
    class Definition
      attr_reader :commands, :components

      def initialize
        @commands = []
        @components = []
      end

      def command(name, description, klass = nil, &block)
        cmd = Command.new(name: name.to_sym, description: description, standalone: klass, subcommands: {}, groups: {})
        CommandBuilder.new(cmd).instance_eval(&block) if block
        @commands << cmd
      end

      # A button/modal handler; its custom_id key + params come from the class.
      def component(klass)
        @components << klass
      end
    end

    class CommandBuilder
      def initialize(command) = @command = command
      def subcommand(name, klass) = @command.subcommands[name.to_sym] = klass

      def group(name, description, &block)
        group = Group.new(name: name.to_sym, description: description, subcommands: {})
        GroupBuilder.new(group).instance_eval(&block)
        @command.groups[name.to_sym] = group
      end
    end

    class GroupBuilder
      def initialize(group) = @group = group
      def subcommand(name, klass) = @group.subcommands[name.to_sym] = klass
    end
  end
end
