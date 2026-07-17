module Memberships
  # A role change Discord refused or can't perform (missing permission, role
  # hierarchy, member gone). Raised by RoleManager and RestRoleManager;
  # messages are officer-facing.
  class RoleError < StandardError; end
end
