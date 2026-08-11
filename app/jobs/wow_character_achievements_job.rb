# Capture one character's career achievements (AOTC, Cutting Edge, Gladiator).
#
# Its own job rather than part of the hourly refresh because the request is
# heavy (~3,600 entries) and the data is near-static once earned.
class WowCharacterAchievementsJob < ApplicationJob
  queue_as :default

  retry_on BattleNet::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(character_id, client: nil)
    character = WowCharacter.find_by(id: character_id) or return

    result = BattleNet::RefreshCharacterAchievements.call(character, client: client)
    Rails.logger.info("[wow] #{character.full_name} achievements: " \
                      "#{result.stored} kept of #{result.scanned} scanned")
  rescue BattleNet::Client::Unauthorized
    BattleNet::Client.expire_app_token
    raise
  end
end
