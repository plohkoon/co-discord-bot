# Posts the immediate single heads-up to the team's lead/review channel the
# moment a raider calls out, enqueued by Absences::Create. Best-effort: a
# vanished channel or a permission refusal is a logged no-op; a transient error
# propagates so retry_on takes over.
class AbsenceLeadNotifyJob < ApplicationJob
  queue_as :default

  retry_on Discord::BotApi::Error, wait: :polynomially_longer, attempts: 5

  def perform(guild_id:, absence_id:, api: Discord::BotApi.new)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      absence = Absence.find_by(id: absence_id) or next
      notify(absence, guild, api)
    end
  end

  private

  def notify(absence, guild, api)
    team = absence.team
    channel_id = team.notify_channel_id or return

    # Midday guild-local so Discord's <t:…:D> (rendered in each viewer's own
    # zone) shows the same calendar date to everyone.
    day = absence.absence_on.in_time_zone(guild.tz).change(hour: 12).to_i
    content = +"<@&#{team.officer_role_id}> 📅 #{absence.mention} called out of **#{team.name}** on <t:#{day}:D>"
    content << " — #{absence.note.strip}" if absence.note.present?

    api.create_message(channel_id, {
      "content" => content,
      "allowed_mentions" => { "parse" => [], "roles" => [ team.officer_role_id.to_s ] }
    })
  rescue Discord::BotApi::NotFound
    # Channel gone or the bot can't post there (Forbidden < NotFound) — the
    # call-out is recorded; the heads-up is best-effort.
    nil
  end
end
