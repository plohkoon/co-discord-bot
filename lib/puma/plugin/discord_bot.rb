# frozen_string_literal: true

require "puma/plugin"

# Boots the co-bot Discord gateway together with Puma, mirroring the Solid Queue
# Puma plugin: it forks a supervised CHILD process (its own AR connection pool +
# crash isolation), tied to Puma's lifecycle so `bin/rails server` starts web +
# jobs + bot together and stops them together.
#
# Enable in config/puma.rb with `plugin :discord_bot if ENV["RUN_DISCORD_BOT"]`.
Puma::Plugin.create do
  def start(launcher)
    @log_writer = launcher.log_writer
    @puma_pid = $$

    # If the bot child dies, bring Puma down too (so the process manager restarts
    # the whole unit).
    in_background { monitor_bot }

    hook_booted(launcher) do
      @bot_pid = fork do
        # A fork inherits the parent's DB connections; discard them so the child
        # opens its own pool.
        ActiveRecord::Base.connection_handler.clear_all_connections! if defined?(ActiveRecord)
        Thread.new { monitor_puma }
        CoBot::Runner.run_supervised
      end
      log "forked co-bot gateway (pid #{@bot_pid})"
    end

    hook_stopped(launcher)  { stop_bot }
    hook_restart(launcher)  { stop_bot }
  end

  private

  def log(message) = @log_writer.log("[co-bot plugin] #{message}")

  # Puma 6 vs 7 renamed the lifecycle hooks; support both (same shim Solid Queue uses).
  def puma7? = Gem::Version.new(Puma::Const::VERSION) >= Gem::Version.new("7")
  def hook_booted(l, &b)  = puma7? ? l.events.after_booted(&b)   : l.events.on_booted(&b)
  def hook_stopped(l, &b) = puma7? ? l.events.after_stopped(&b)  : l.events.on_stopped(&b)
  def hook_restart(l, &b) = puma7? ? l.events.before_restart(&b) : l.events.on_restart(&b)

  # In the Puma master: SIGINT the bot child and reap it on shutdown/restart.
  def stop_bot
    return unless @bot_pid

    log "stopping co-bot gateway (pid #{@bot_pid})"
    Process.kill(:INT, @bot_pid)
    Process.wait(@bot_pid)
    @bot_pid = nil
  rescue Errno::ESRCH, Errno::ECHILD
    @bot_pid = nil # so monitor_bot doesn't misfire on the reaped pid during a phased restart
  end

  # In the Puma master (background thread): watch the bot child.
  def monitor_bot
    loop do
      if bot_dead?
        log "co-bot gateway exited; stopping Puma"
        Process.kill(:INT, @puma_pid) rescue nil
        break
      end
      sleep 2
    end
  end

  # In the bot child (background thread): if Puma (our parent) is gone, trigger
  # our own graceful shutdown.
  def monitor_puma
    loop do
      if Process.ppid != @puma_pid
        Process.kill(:INT, Process.pid) rescue nil
        break
      end
      sleep 2
    end
  end

  def bot_dead?
    return false unless @bot_pid

    !!Process.waitpid(@bot_pid, Process::WNOHANG)
  rescue Errno::ECHILD, Errno::ESRCH
    true
  end
end
