# One "this person got that rule's role" record. Exists so the hourly sweep
# never re-spends a REST call on someone already rewarded — and, for
# auto_revoke rules, so the sweep knows exactly whose qualification to
# re-check. Deleted when the role is auto-revoked; deleting the parent rule
# removes these rows but never touches the Discord roles themselves.
class RoleRewardGrant < ApplicationRecord
  belongs_to :role_reward

  validates :discord_user_id, presence: true, uniqueness: { scope: :role_reward_id }
  validates :granted_at, presence: true
end
