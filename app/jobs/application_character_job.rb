# Resolve the character an applicant named, claim it for them, and start
# gathering its data.
#
# Runs OUT of band from the application itself, deliberately. Resolution costs a
# Blizzard round trip and an application must never be lost — or even delayed —
# because someone misspelt their own character. The application is already saved
# and the officers already notified by the time this runs.
#
# A typo is the expected failure, not an exception: the application keeps what
# they typed, and they get a DM telling them what happened so they can fix it.
class ApplicationCharacterJob < ApplicationJob
  queue_as :default

  retry_on BattleNet::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(application_id:, guild_id:, client: nil)
    guild = Guild.find_by(id: guild_id) or return

    ActsAsTenant.with_tenant(guild) do
      application = TeamApplication.find_by(id: application_id) or next
      next if application.character_input.blank? || application.wow_character_id.present?


      # A shadow record if this is the first co-bot has heard of them — an
      # applicant almost certainly hasn't signed into the web app.
      user = User.for_discord(application.discord_user_id, username: application.discord_username)

      result = WowCharacters::Resolve.call(
        user: user, input: application.character_input,
        region: application.team.region, client: client
      )

      result.ok? ? record(application, user, result) : notify_unresolved(application, result)
      # Stamped whichever way it went — this is what turns "still looking" into
      # a definite answer for everything reading the application.
      application.update!(character_resolved_at: Time.current)

      # The review message was posted saying "Loading raider data…". Repaint it
      # now that resolution is settled — a typo becomes "Cannot load raider
      # data" immediately, and a success keeps saying "loading" until the
      # refresh lands and repaints again.
      Applications::RefreshReviewMessage.call(application.reload)
    end
  end

  private

  def record(application, user, result)
    character = result.character
    application.update!(wow_character: character)
    # What they applied on is what they intend to play on this team.
    application.team_membership&.update!(wow_character: character)
    # First character someone gets becomes their main; never overrides a choice.
    WowCharacters::SetMain.ensure(user)
    # The refresh repaints the review message itself once it has data (see
    # WowCharacterRefreshJob), so this doesn't have to gather inline to make the
    # summary useful — and shouldn't, since doing so would drag four external
    # services into the critical path of resolving a name.
    WowCharacterRefreshJob.perform_later(character.id)

    Rails.logger.info("[wow] application #{application.id} resolved to #{character.full_name}")
  end

  # A button, because a button may open a modal and a modal submit may not —
  # which is why correction has to happen on a follow-up message rather than
  # when the application is submitted.
  def fix_character_view(application)
    view = Discordrb::Webhooks::View.new
    view.row do |row|
      row.button(label: "✏️ Fix character", style: :primary,
                 custom_id: CoBot::CommandRegistry.custom_id("fixchar", application.id))
    end
    view
  end

  # Best-effort, like every other DM here: a closed DM is swallowed rather than
  # retried. The application stands either way — the officers still see what was
  # typed, and the applicant can correct it.
  def notify_unresolved(application, result)
    Rails.logger.info("[wow] application #{application.id} character unresolved: #{result.input.inspect}")

    Notifications::DirectMessage.call(
      user_id: application.discord_user_id,
      content: "Your application to **#{application.team.name}** is in — but I couldn't find a " \
               "character called **#{result.input}**. #{result.error}" \
               "\n\nNothing is lost: the team can still review your application. Use the button " \
               "below to correct it yourself.",
      components: fix_character_view(application)
    )
  end
end
