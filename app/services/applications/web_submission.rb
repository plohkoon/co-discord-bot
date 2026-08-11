module Applications
  # Adapts a web form submission to the modal-event interface that
  # Applications::Submit reads (`event.user.id` / `.username` and
  # `event.value("q:<id>")` / `value("character")`), so the web apply page and
  # the Discord modal share one business path instead of forking it.
  class WebSubmission
    # Quacks like a Discord user: `id` is the snowflake, `username` the handle.
    Actor = Data.define(:id, :username)

    # user: a signed-in User (has discord_id + username); values: string-keyed
    # hash of "q:<question id>" answers plus optional "character".
    def initialize(user:, values:)
      @user = user
      @values = values.transform_keys(&:to_s)
    end

    def user = Actor.new(id: @user.discord_id, username: @user.username.to_s)

    def value(key) = @values[key.to_s]
  end
end
