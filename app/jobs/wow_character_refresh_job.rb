# Refresh one character's live data from Blizzard. One character per job so a
# single bad character can't stall a whole account, and a retry re-fetches only
# what failed. Enqueued by WowCharacterSweepJob, by BattleNet::LinkAccount right
# after a link, and by the manual button on /account.
class WowCharacterRefreshJob < ApplicationJob
  queue_as :default

  # Blizzard's own hiccups (5xx, timeouts) — back off rather than give up.
  # Unauthorized is a subclass of Error, so this covers a rotated app token too.
  # A 404 is not an error here: RefreshCharacter records it as :missing.
  retry_on BattleNet::Client::Error, wait: :polynomially_longer, attempts: 4

  def perform(character_id, client: nil, raider_io: nil, warcraft_logs: nil, pvp: nil, professions: nil)
    character = WowCharacter.find_by(id: character_id) or return

    result = BattleNet::RefreshCharacter.call(character, client: client)
    Rails.logger.info("[wow] #{character.full_name} refresh -> #{result.status}") unless result.ok?
    return if result.status == :missing

    enrich_from_raider_io(character, raider_io)
    enrich_from_warcraft_logs(character, warcraft_logs)
    enrich_from_pvp(character, pvp || client)
    enrich_from_professions(character, professions || client)
    repaint_pending_applications(character)
  rescue BattleNet::Client::Unauthorized
    # The cached app token was revoked or rotated. Drop it here — before the
    # retry, not after retries are exhausted — so the next attempt mints a fresh
    # one instead of replaying the dead one.
    BattleNet::Client.expire_app_token
    raise
  end

  private

  # An application showing "Loading raider data…" is waiting on exactly this —
  # so the refresh, not the resolver, is what knows when there is something to
  # show. Doing it here also keeps a long-open application's summary current
  # for free, every time the hourly sweep touches the character.
  #
  # TeamApplication is guild-scoped; read outside a tenant it is unscoped, which
  # is what lets one character's refresh reach applications in any guild.
  def repaint_pending_applications(character)
    TeamApplication.where(wow_character_id: character.id).pending.find_each do |application|
      guild = Guild.find_by(id: application.guild_id) or next

      ActsAsTenant.with_tenant(guild) { Applications::RefreshReviewMessage.call(application) }
    end
  rescue StandardError => e
    # A repaint must never cost the data that was just gathered.
    Rails.logger.warn("[wow] repainting applications for #{character.full_name} failed: #{e.class}: #{e.message}")
  end

  # Raider.io adds raid progression and the role split — real value, but strictly
  # supplementary. It is deliberately NOT allowed to fail the job: Blizzard's
  # data is already saved by this point, Raider.io's rate limit is far tighter
  # (200/min vs 36,000/hour), and retrying the whole job would re-spend Blizzard
  # requests to fix a Raider.io problem. A miss just waits for the next sweep.
  def enrich_from_raider_io(character, client)
    RaiderIo::RefreshCharacter.call(character, client: client || RaiderIo::Client.new)
  rescue RaiderIo::Client::Error => e
    Rails.logger.info("[wow] raider.io skipped for #{character.full_name}: #{e.class}: #{e.message}")
  end

  # PvP rides on the same Blizzard token as the gear refresh, so it costs no new
  # credentials. It is NOT best-effort in the same sense as the others: Blizzard
  # serves a character's rating for the current season only, so a skipped
  # refresh loses that data permanently rather than deferring it. Failures are
  # still contained — one character's PvP shouldn't cost their gear — but they
  # are logged at warn, not info.
  def enrich_from_pvp(character, client)
    BattleNet::RefreshCharacterPvp.call(character, client: client)
  rescue BattleNet::Client::Unauthorized
    raise # token problem — let the caller evict and retry
  rescue BattleNet::Client::Error => e
    Rails.logger.warn("[pvp] refresh failed for #{character.full_name}: #{e.class}: #{e.message}")
  end

  # Professions self-throttle to weekly inside the service, so calling this on
  # every hourly pass costs one request per character per week, not per hour.
  def enrich_from_professions(character, client)
    BattleNet::RefreshCharacterProfessions.call(character, client: client)
  rescue BattleNet::Client::Unauthorized
    raise
  rescue BattleNet::Client::Error => e
    Rails.logger.info("[wow] professions skipped for #{character.full_name}: #{e.class}: #{e.message}")
  end

  # Also strictly supplementary, and for a sharper reason than Raider.io:
  # Warcraft Logs meters by POINTS (3,600/hour), not requests, and most
  # characters have never been in a logged raid at all. Skipped entirely without
  # credentials, so the whole WoW pipeline works before anyone configures it.
  def enrich_from_warcraft_logs(character, client)
    return unless client || WarcraftLogs::Client.configured?
    return if character.logs_missing?

    WarcraftLogs::RefreshCharacter.call(character, client: client || WarcraftLogs::Client.new)
  rescue WarcraftLogs::Client::Unauthorized => e
    # Rotated or revoked credentials — drop the cached token so the next pass
    # mints a fresh one, then carry on rather than failing the whole refresh.
    WarcraftLogs::Client.expire_access_token
    Rails.logger.warn("[wow] warcraft logs auth failed: #{e.message}")
  rescue WarcraftLogs::Client::Error => e
    Rails.logger.info("[wow] warcraft logs skipped for #{character.full_name}: #{e.class}: #{e.message}")
  end
end
