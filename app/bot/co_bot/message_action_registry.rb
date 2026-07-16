module CoBot
  # The message-action manifest (config/message_actions.rb) lists the automatic
  # message actions that are live, mirroring how config/commands.rb works for
  # slash commands. Each action's class is discovered from its name
  # (`action :meat_react` -> MessageActions::MeatReact); pass `class:` to override.
  module MessageActionRegistry
    class << self
      def draw(&block)
        @actions = []
        Builder.new(@actions).instance_eval(&block)
        @actions
      end

      def actions = @actions ||= load_manifest

      def reload!
        @actions = nil
        actions
      end

      # Action classes whose matcher fires on this content, in manifest order.
      def matching(content)
        actions.select { |klass| klass.matches?(content) }
      end

      private

      def load_manifest
        @actions = nil
        Kernel.load(Rails.root.join("config/message_actions.rb").to_s)
        @actions
      end
    end

    class Builder
      def initialize(collection)
        @collection = collection
      end

      def action(name, klass: nil)
        @collection << (klass || "MessageActions::#{name.to_s.camelize}".constantize)
      rescue NameError
        raise "Message action manifest: no class MessageActions::#{name.to_s.camelize} for `action :#{name}` (pass `class:` to override)"
      end
    end
  end
end
