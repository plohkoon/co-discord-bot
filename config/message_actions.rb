# The message-action manifest — every automatic response to ordinary messages,
# at a glance. One class per action in app/bot/message_actions/; each class
# declares its own matcher (`match word:/contains:/pattern:`) and `perform`.
# The class is discovered from the action name (action :meat_react ->
# MessageActions::MeatReact); pass `class:` only to override.
#
# Reading message text needs the **Message Content privileged intent** —
# enable it in the Developer Portal > Bot for every app (dev AND prod), or
# message.content arrives empty and no action will ever match.

CoBot::MessageActionRegistry.draw do
  # action :meat_react
end
