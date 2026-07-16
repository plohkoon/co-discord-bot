# Base for all Discord application commands (Discord's own term for slash
# commands and the interactions they spawn). This is the bot's ApplicationController:
# concrete commands live in app/commands, define actions + before_action filters,
# and are dispatched by CoBot::Runner per the routes in config/commands.rb.
#
# Each instance handles exactly one interaction. The runner has already wrapped
# us in the Rails executor and set the current guild (acts_as_tenant), so every
# query here is auto-scoped to this guild.
class ApplicationCommand
  class << self
    def before_actions
      @before_actions ||= (superclass.respond_to?(:before_actions) ? superclass.before_actions.dup : [])
    end

    # before_action :name, only: [...], except: [...]   (or a block)
    def before_action(name = nil, only: nil, except: nil, &block)
      before_actions << { name: name, block: block, only: wrap(only), except: wrap(except) }
    end

    def wrap(value) = value.nil? ? nil : Array(value).map(&:to_sym)
  end

  attr_reader :event, :guild, :params

  def initialize(event:, guild:, params: {})
    @event = event
    @guild = guild
    @params = params || {}
    @performed = false
  end

  def process(action)
    @action = action.to_sym
    catch(:halt) do
      run_before_actions
      public_send(@action)
    end
  end

  private

  # A before_action "halts" like ActionController: if it produces a response,
  # the action is skipped.
  def run_before_actions
    self.class.before_actions.each do |filter|
      next unless filter_applies?(filter)

      filter[:block] ? instance_exec(&filter[:block]) : send(filter[:name])
      throw :halt if @performed
    end
  end

  def filter_applies?(filter)
    return false if filter[:only] && !filter[:only].include?(@action)
    return false if filter[:except]&.include?(@action)

    true
  end

  # --- option / context accessors ---
  def option(name) = event.options[name.to_s]
  def current_user = event.user
  def current_user_id = event.user&.id
  def current_guild = guild
  def server = event.server

  # --- response API: each call is exactly one interaction ack ---
  def respond(content = nil, ephemeral: true, embeds: nil, components: nil)
    ack!
    event.respond(content: content, ephemeral: ephemeral,
                  embeds: Array(embeds).compact.presence, components: components)
  end

  def show_modal(title:, custom_id:, &block)
    ack!
    event.show_modal(title: title.to_s[0, 45], custom_id: custom_id, &block)
  end

  def update_message(content: nil, embeds: nil, components: [])
    ack!
    event.update_message(content: content, embeds: Array(embeds).compact.presence, components: components)
  end

  def ack!
    raise "this interaction has already been answered" if @performed

    @performed = true
  end
end
