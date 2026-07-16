require "discordrb"

module CoBot
  # Owns the single Discordrb::Bot and dispatches interactions to the command
  # classes discovered by CoBot::CommandRegistry. Host-agnostic: bin/bot and the
  # Puma plugin both just call CoBot::Runner.start / .stop.
  class Runner
    class << self
      def instance = @instance ||= new
      def start = instance.start
      def stop  = @instance&.stop
      def reset! = (@instance = nil)

      # Blocking, supervised run for a dedicated bot process (bin/bot / Puma fork).
      def run_supervised
        @shutdown = false
        install_signal_traps

        if ENV["DISCORD_BOT_TOKEN"].to_s.strip.empty?
          Rails.logger.warn("[co-bot] DISCORD_BOT_TOKEN is not set — gateway will stay idle. Add it and restart.")
          sleep 1 until @shutdown
          return
        end

        backoff = 1
        until @shutdown
          begin
            start
          rescue => e
            Rails.logger.error("[co-bot] gateway loop crashed: #{e.class}: #{e.message}")
            Rails.logger.error(Array(e.backtrace).first(8).join("\n"))
          end
          break if @shutdown

          Rails.logger.warn("[co-bot] gateway stopped; restarting in #{backoff}s")
          backoff.times { break if @shutdown; sleep 1 }
          backoff = [ backoff * 2, 30 ].min
          reset!
        end
        Rails.logger.info("[co-bot] supervised loop exited")
      end

      def install_signal_traps
        %w[INT TERM].each do |signal|
          Signal.trap(signal) do
            @shutdown = true
            Thread.new { stop }
          end
        end
      end

      # Wrap a discordrb handler body. discordrb dispatches every gateway event on
      # its own bare Thread, so DB work MUST run inside the Rails executor.
      def handle(label)
        Rails.application.executor.wrap { yield }
      rescue => e
        Rails.logger.error("[co-bot] #{label} failed: #{e.class}: #{e.message}")
        Rails.logger.error(Array(e.backtrace).first(8).join("\n"))
        nil
      end
    end

    attr_reader :bot

    def initialize
      token = ENV["DISCORD_BOT_TOKEN"].to_s
      raise "DISCORD_BOT_TOKEN is not set" if token.strip.empty?

      @bot = Discordrb::Bot.new(token: token, intents: %i[servers server_members])
      install
    end

    def start
      Rails.logger.info("[co-bot] connecting to the Discord gateway…")
      @bot.run
    end

    def stop
      Rails.logger.info("[co-bot] disconnecting from the Discord gateway…")
      @bot.stop
    end

    private

    def install
      install_commands
      install_components
      @bot.autocomplete { |event| dispatch_autocomplete(event) }

      @bot.ready { |_event| self.class.handle("ready") { sync_all_guilds } }
      @bot.server_create { |event| self.class.handle("server_create") { sync_guild(event.server) } }

      @bot.member_update do |event|
        self.class.handle("member_update") { Memberships::RoleSync.reconcile(server: event.server, member: event.user, roles: event.roles) }
      end
      @bot.member_leave do |event|
        self.class.handle("member_leave") { Memberships::RoleSync.on_leave(server: event.server, user_id: event.user&.id) }
      end
    end

    def install_commands
      CommandRegistry.dispatch_table.each do |path, klass|
        handler = ->(event) { dispatch(klass, event) }
        case path.size
        when 1 then @bot.application_command(path[0], &handler)
        when 2 then @bot.application_command(path[0]).subcommand(path[1], &handler)
        when 3 then @bot.application_command(path[0]).group(path[1]).subcommand(path[2], &handler)
        end
      end
    end

    def install_components
      CommandRegistry.components.each do |klass|
        spec = klass.component_spec
        matcher = /\A#{Regexp.escape(spec[:key])}:/
        handler = ->(event) { dispatch_component(klass, event) }
        spec[:kind] == :modal ? @bot.modal_submit(custom_id: matcher, &handler) : @bot.button(custom_id: matcher, &handler)
      end
    end

    def dispatch(klass, event)
      self.class.handle(klass.name) do
        with_tenant(event) { |guild| klass.new(event: event, guild: guild).process }
      end
    end

    def dispatch_component(klass, event)
      values = event.custom_id.to_s.split(":")[1..] || []
      params = klass.component_spec[:params].zip(values).to_h
      self.class.handle(klass.name) do
        with_tenant(event) { |guild| klass.new(event: event, guild: guild, params: params).process }
      end
    end

    def dispatch_autocomplete(event)
      self.class.handle("autocomplete") do
        klass = CommandRegistry.command_for(command_name: event.command_name,
                                            subcommand_group: event.subcommand_group,
                                            subcommand: event.subcommand)
        next unless klass

        with_tenant(event) { |guild| klass.new(event: event, guild: guild).autocomplete(event.focused) }
      end
    end

    def with_tenant(event)
      unless event.server
        event.respond(content: "I can't find this server — I may have been removed from it.", ephemeral: true) rescue nil
        return
      end

      guild = Guild.sync_from_discord(id: event.server.id, name: event.server.name)
      ActsAsTenant.with_tenant(guild) { yield guild }
    end

    def sync_all_guilds = @bot.servers.each_value { |server| sync_guild(server) }

    def sync_guild(server)
      Guild.sync_from_discord(id: server.id, name: server.name)
      CommandRegistry.register(@bot, server.id)
      Rails.logger.info("[co-bot] registered commands for #{server.name} (#{server.id})")
    end
  end
end
