# Enqueue career-achievement refreshes for characters that need one.
#
# Weekly and small-batched, unlike the hourly gear sweep: the request is heavy
# (~3,600 entries per character) and achievements barely move once earned — the
# only thing that changes them is a new tier's AOTC or a season's Gladiator.
#
# Never-fetched characters go first, so a freshly linked account gets its
# credentials before an existing one gets a routine top-up.
class WowCharacterAchievementsSweepJob < ApplicationJob
  queue_as :default

  MIN_LEVEL = WowCharacterSweepJob::MIN_LEVEL
  REFRESH_AFTER = 30.days
  BATCH = 100

  def perform(now: Time.current, limit: BATCH)
    due = WowCharacter.refreshable(min_level: MIN_LEVEL)
                      .where(achievements_refreshed_at: ...(now - REFRESH_AFTER))
                      .or(WowCharacter.refreshable(min_level: MIN_LEVEL)
                                      .where(achievements_refreshed_at: nil))
                      .order(Arel.sql("achievements_refreshed_at IS NULL DESC"),
                             achievements_refreshed_at: :asc)
                      .limit(limit)

    ids = due.pluck(:id)
    ids.each { |id| WowCharacterAchievementsJob.perform_later(id) }
    Rails.logger.info("[wow] achievements sweep enqueued #{ids.size}") if ids.any?
    ids.size
  end
end
