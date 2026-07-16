module CoBot
  # Discovers Commands::Base subclasses and turns them into the Discord command
  # tree (registration) + dispatch lookups. Replaces the old router + commands.rb.
  module CommandRegistry
    ROOT = "app/bot/commands".freeze

    module_function

    def load!
      loader = Rails.autoloaders.main
      if loader.respond_to?(:eager_load_dir)
        loader.eager_load_dir(Rails.root.join(ROOT))
      else
        Dir.glob(Rails.root.join(ROOT, "**/*.rb")).sort.each { |f| require f }
      end
    rescue => e
      Rails.logger.error("[co-bot] loading commands failed: #{e.class}: #{e.message}")
    end

    def all = (load!; Commands::Base.registry.uniq)
    def commands = all.reject(&:component?)
    def components = all.select(&:component?)

    def custom_id(key, *values) = [ key, *values ].join(":")

    def command_for(command_name:, subcommand_group: nil, subcommand: nil)
      path = [ command_name, subcommand_group, subcommand ].compact.map(&:to_s)
      commands.find { |klass| klass.path == path }
    end

    # (Re)register every command for one guild. register_application_command upserts.
    def register(bot, guild_id)
      tree.each do |command_name, node|
        bot.register_application_command(command_name, node[:description], server_id: guild_id) do |builder|
          if node[:standalone]
            apply_options(builder, node[:standalone].command_options)
          else
            node[:subcommands].each do |sub_name, klass|
              builder.subcommand(sub_name, klass.description || sub_name.to_s) { |sc| apply_options(sc, klass.command_options) }
            end
            node[:groups].each do |group_name, subs|
              builder.subcommand_group(group_name, group_description(command_name, group_name)) do |grp|
                subs.each { |sub_name, klass| grp.subcommand(sub_name, klass.description || sub_name.to_s) { |sc| apply_options(sc, klass.command_options) } }
              end
            end
          end
        end
      end
    end

    def tree
      nodes = {}
      commands.each do |klass|
        path = klass.path
        command = path.first.to_sym
        node = (nodes[command] ||= { description: command_description(command), standalone: nil, subcommands: {}, groups: {} })
        case path.size
        when 1
          node[:standalone] = klass
          node[:description] = klass.description || node[:description]
        when 2
          node[:subcommands][path[1].to_sym] = klass
        when 3
          (node[:groups][path[1].to_sym] ||= {})[path[2].to_sym] = klass
        end
      end
      nodes
    end

    def command_description(command)
      const = "Commands::#{command.to_s.camelize}".safe_constantize
      (const&.const_defined?(:DESCRIPTION) && const::DESCRIPTION) || "#{command.to_s.humanize} commands"
    end

    def group_description(command, group)
      const = "Commands::#{command.to_s.camelize}::#{group.to_s.camelize}".safe_constantize
      (const&.const_defined?(:DESCRIPTION) && const::DESCRIPTION) || group.to_s.humanize
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
end
