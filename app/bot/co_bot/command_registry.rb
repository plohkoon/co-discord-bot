module CoBot
  # The command manifest (config/commands.rb) declares the command tree with a
  # single nested `command` keyword — a command with children is a subcommand
  # group, a command without children is a leaf. Each node's class is discovered
  # from its path (Commands::Team::Member::Accept) unless `class:` overrides it.
  module CommandRegistry
    Node = Struct.new(:name, :path, :description, :klass, :children, keyword_init: true) do
      def leaf? = children.empty?
    end

    class << self
      # --- manifest DSL ---
      def draw(&block)
        @definition = Definition.new
        Builder.new(@definition, @definition.commands, []).instance_eval(&block)
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

      # path (array of symbols) -> command class, for every leaf.
      def dispatch_table
        table = {}
        each_leaf(definition.commands) { |node| table[node.path] = class_for(node) }
        table
      end

      def command_for(command_name:, subcommand_group: nil, subcommand: nil)
        path = [ command_name, subcommand_group, subcommand ].compact.map(&:to_sym)
        dispatch_table[path]
      end

      # Sync this guild's commands to the manifest: upsert each top-level command
      # (which replaces its whole subtree), then delete any command that's no
      # longer in the manifest (e.g. the old top-level /apply after it moved).
      def register(bot, guild_id)
        keep = definition.commands.map { |command| command.name.to_s }.to_set

        definition.commands.each do |command|
          bot.register_application_command(command.name, description_for(command), server_id: guild_id) do |builder|
            if command.leaf?
              apply_options(builder, class_for(command).command_options)
            else
              command.children.each { |child| register_child(builder, child) }
            end
          end
        end

        prune_stale(bot, guild_id, keep)
      end

      # The class for a leaf node — from `class:` or discovered from the path.
      def class_for(node)
        return node.klass if node.klass

        const = "Commands::#{node.path.map { |part| part.to_s.camelize }.join('::')}"
        const.constantize
      rescue NameError
        raise "Command manifest: no class #{const} for `/#{node.path.join(' ')}` (pass `class:` to override)"
      end

      private

      # Delete any guild command not in the manifest. register_application_command
      # only upserts, so removed top-level commands would otherwise linger.
      def prune_stale(bot, guild_id, keep)
        bot.get_application_commands(server_id: guild_id).each do |command|
          next if keep.include?(command.name.to_s)

          command.delete
          Rails.logger.info("[co-bot] removed stale command /#{command.name}")
        end
      rescue => e
        Rails.logger.warn("[co-bot] pruning stale commands failed: #{e.class}: #{e.message}")
      end

      def register_child(builder, child)
        if child.leaf?
          builder.subcommand(child.name, description_for(child)) { |sc| apply_options(sc, class_for(child).command_options) }
        else
          builder.subcommand_group(child.name, description_for(child)) do |group|
            child.children.each { |leaf| group.subcommand(leaf.name, description_for(leaf)) { |sc| apply_options(sc, class_for(leaf).command_options) } }
          end
        end
      end

      def description_for(node)
        return node.description if node.description.present?

        node.leaf? ? (class_for(node).description || node.name.to_s.humanize) : node.name.to_s.humanize
      end

      def each_leaf(nodes, &block)
        nodes.each { |node| node.leaf? ? block.call(node) : each_leaf(node.children, &block) }
      end

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

    class Definition
      attr_reader :commands, :components

      def initialize
        @commands = []
        @components = []
      end
    end

    # Recursive builder: `command` nests, `component` registers a handler class.
    class Builder
      def initialize(definition, collection, parent_path)
        @definition = definition
        @collection = collection
        @parent_path = parent_path
      end

      def command(name, description = nil, klass: nil, &block)
        path = @parent_path + [ name.to_sym ]
        node = Node.new(name: name.to_sym, path: path, description: description, klass: klass, children: [])
        Builder.new(@definition, node.children, path).instance_eval(&block) if block
        @collection << node
      end

      def component(klass)
        @definition.components << klass
      end
    end
  end
end
