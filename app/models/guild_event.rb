# A native Discord scheduled event, mirrored locally so the bot can own the
# *channel* half of it — Discord's Events tab handles the calendar, RSVPs and
# the start notification, but never posts anything to a text channel.
#
# The row exists to remember what we posted (so it can be edited/deleted later)
# and which transitions have already been acted on. Discord remains the source
# of truth for the event itself; nothing here is ever pushed back.
class GuildEvent < ApplicationRecord
  include GuildScoped

  # Values match Discord's guild scheduled event status enum exactly.
  enum :status, { scheduled: 1, active: 2, completed: 3, canceled: 4 }, default: :scheduled

  validates :discord_event_id, presence: true, uniqueness: { scope: :guild_id }

  scope :live, -> { where(cleaned_up_at: nil) }

  # The public event link. Discord unfurls this into a native event card that
  # keeps *itself* up to date — including flipping to an ended state when the
  # event finishes, which is why the announcement is a link rather than an
  # embed we'd have to repaint ourselves.
  def url = "https://discord.com/events/#{guild_id}/#{discord_event_id}"

  def terminal? = completed? || canceled?

  def announced? = announcement_message_id.present?
  def start_posted? = start_message_id.present?
  def cleaned_up? = cleaned_up_at.present?

  # Everything we've posted for this event, newest last.
  def message_ids = [ announcement_message_id, start_message_id ].compact
end
