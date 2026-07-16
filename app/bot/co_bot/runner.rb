require "discordrb"

module CoBot
  # Owns the single Discordrb::Bot and dispatches interactions to app/commands
  # via the routes in config/commands.rb. Host-agnostic: bin/bot and the Puma
  # plugin both just call CoBot::Runner.start / .stop.
  class Runner
    class << self
      def instance = @instance ||= new
      def start = instance.start
      def stop  = @instance&.stop
      def reset! = (@instance = nil)

      # Blocking, supervised run for a dedicated bot process (bin/bot, or the
      # Puma fork). Restarts the gateway with backoff if it crashes, and stops
      # gracefully on SIGINT/SIGTERM.
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
          # Interruptible: a Ruby-block signal trap does NOT abort Kernel#sleep,
          # so poll @shutdown each second to exit within ~1s of a stop signal.
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

      # Wrap a discordrb handler body. discordrb dispatches every gateway event
      # on its own bare Thread, so DB work MUST run inside the Rails executor to
      # return pooled connections and resolve reloadable constants. Rescues so a
      # single bad handler can never take the gateway down.
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

      # servers (GUILDS): guild list on connect + GUILD_CREATE.
      # server_members (PRIVILEGED): GUILD_MEMBER_UPDATE / _REMOVE so we can
      # auto-sync memberships when team roles are granted/removed manually.
      # Enable the Server Members Intent in the Developer Portal for this to work.
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

    def routes = CoBot::Router.definition

    def install
      install_command_handlers
      install_component_handlers
      @bot.autocomplete { |event| dispatch_autocomplete(event) }

      @bot.ready { |_event| self.class.handle("ready") { sync_all_guilds } }
      @bot.server_create { |event| self.class.handle("server_create") { sync_guild(event.server) } }

      # Auto-sync memberships from manual role changes (needs Server Members intent).
      @bot.member_update do |event|
        self.class.handle("member_update") do
          Memberships::RoleSync.reconcile(server: event.server, member: event.user, roles: event.roles)
        end
      end
      @bot.member_leave do |event|
        self.class.handle("member_leave") do
          Memberships::RoleSync.on_leave(server: event.server, user_id: event.user&.id)
        end
      end
    end

    def install_command_handlers
      routes.commands.each do |cmd|
        if cmd.subcommands.any?
          cmd.subcommands.each do |sub|
            @bot.application_command(cmd.name).subcommand(sub.name) { |event| dispatch(sub.action, event) }
          end
        else
          @bot.application_command(cmd.name) { |event| dispatch(cmd.action, event) }
        end
      end
    end

    # Persistent component routes — registered once, before connect, so buttons
    # and modals on messages from previous runs keep working after a restart.
    def install_component_handlers
      routes.components.each do |comp|
        matcher = /\A#{Regexp.escape(comp.key)}:/
        if comp.kind == :modal
          @bot.modal_submit(custom_id: matcher) { |event| dispatch_component(comp, event) }
        else
          @bot.button(custom_id: matcher) { |event| dispatch_component(comp, event) }
        end
      end
    end

    def dispatch(action, event, params = {})
      self.class.handle(action) do
        with_tenant(event) do |guild|
          command_class(action).new(event: event, guild: guild, params: params).process(action_method(action))
        end
      end
    end

    def dispatch_component(comp, event)
      values = event.custom_id.to_s.split(":")[1..] || []
      params = comp.param_names.map(&:to_sym).zip(values).to_h
      dispatch(comp.action, event, params)
    end

    def dispatch_autocomplete(event)
      self.class.handle("autocomplete") do
        cmd = routes.commands.find { |c| c.name.to_s == event.command_name.to_s && c.action }
        next unless cmd

        with_tenant(event) do |guild|
          command_class(cmd.action).new(event: event, guild: guild, params: {}).process(:autocomplete)
        end
      end
    end

    # Set the current guild (tenant) for the duration of the interaction, so all
    # queries auto-scope to this server via acts_as_tenant.
    def with_tenant(event)
      # event.server is nil in DMs or where the bot lacks the bot scope (e.g. an
      # old persistent button after the bot was removed). Never persist a nil id.
      unless event.server
        event.respond(content: "I can't find this server — I may have been removed from it.", ephemeral: true) rescue nil
        return
      end

      guild = Guild.sync_from_discord(id: event.server.id, name: event.server.name)
      ActsAsTenant.with_tenant(guild) { yield guild }
    end

    # "teams#create" -> TeamsCommand (constant lives in app/commands)
    def command_class(action)
      "#{action.split('#').first.camelize}Command".constantize
    end

    def action_method(action) = action.split("#").last

    def sync_all_guilds = @bot.servers.each_value { |server| sync_guild(server) }

    def sync_guild(server)
      Guild.sync_from_discord(id: server.id, name: server.name)
      CoBot::Router.register(@bot, server.id)
      Rails.logger.info("[co-bot] registered commands for #{server.name} (#{server.id})")
    end
  end
end
