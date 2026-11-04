# Every table scoped to a Discord guild. Uses acts_as_tenant so queries are
# auto-scoped to the current guild and guild_id is auto-filled on create — the
# current guild is set at the two entry points (web before_action, bot dispatch).
module GuildScoped
  extend ActiveSupport::Concern

  included do
    acts_as_tenant(:guild)
  end

  # acts_as_tenant 2.x validates every belongs_to on save: the associated row
  # must exist and belong to the same guild. That's exactly right between
  # guild-scoped models (a team can't point at another guild's category), so
  # those keep the check.
  #
  # It's wrong for associations into cross-guild models — User and WowCharacter
  # are per-person, not per-guild, so there is no guild to compare. Worse, the
  # "must exist" half rejects the ordinary case: TeamMembership#user is keyed
  # on discord_user_id and is nil for every member who has never signed into
  # the web app, so the check would refuse to create their membership at all.
  def validate_tenant_association?(reflection)
    return true if reflection.polymorphic?

    target = reflection.klass
    target.respond_to?(:scoped_by_tenant?) && target.scoped_by_tenant?
  end
end
