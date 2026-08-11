# The recurring half of the WoW refresh: find characters whose data has gone
# stale and enqueue one WowCharacterRefreshJob each.
#
# Runs on the app's client-credentials token, so it is independent of any user's
# expired OAuth grant — this is what keeps ilvl and M+ scores current between
# link ceremonies.
#
# Two deliberate limits, because a linked account brings ~50 characters and most
# of them are bank alts nobody will ever look at:
#   MIN_LEVEL — skip characters too low to have meaningful gear or a score.
#   BATCH     — cap how many refreshes one pass enqueues, so a burst of new
#               links spreads over several passes instead of one spike.
# Both are cost controls, not correctness: oldest-refreshed-first ordering means
# nothing is starved, it just waits its turn.
class WowCharacterSweepJob < ApplicationJob
  queue_as :default

  MIN_LEVEL = 70
  REFRESH_AFTER = 6.hours
  BATCH = 250

  def perform(now: Time.current, limit: BATCH)
    due = WowCharacter.refreshable(min_level: MIN_LEVEL)
                      .stale(before: now - REFRESH_AFTER)
                      .oldest_first
                      .limit(limit)

    ids = due.pluck(:id)
    ids.each { |id| WowCharacterRefreshJob.perform_later(id) }
    Rails.logger.info("[wow] sweep enqueued #{ids.size} character refreshes") if ids.any?
    ids.size
  end
end
