module Memberships
  # The narrow "member isn't in the guild" case, split from RoleError because
  # it is EXPECTED for web applicants who applied before joining the server:
  # accepting them must not fail, only skip the grant (MemberJoinReconcileJob
  # picks it up when they join). Still a RoleError subclass so callers that
  # don't care keep treating it as a refusal. Own file so Zeitwerk can resolve
  # the constant on first reference.
  class MemberNotInGuild < RoleError; end
end
