# Local mirror of one holder of a team's officer role. Maintained by
# Memberships::RoleSync (member_update / member_leave) and seeded/pruned by
# Memberships::Backfill at team creation — never derived by paging the guild's
# member list at render time. Used for the roster's "Team Leads" line;
# authorization checks still read live roles.
class TeamOfficer < ApplicationRecord
  include GuildScoped

  belongs_to :team

  validates :discord_user_id, presence: true

  scope :ordered, -> { order(:discord_username, :discord_user_id) }
end
