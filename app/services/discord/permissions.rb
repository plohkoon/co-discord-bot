module Discord
  # Discord permission bitfield helpers. A guild role carries a `permissions`
  # field — a decimal STRING of the permission integer (bits exceed 32-bit, so
  # Discord serialises it as a string). We use this to keep the web role
  # pickers from ever offering a role that carries a dangerous permission: a
  # Manage-Server user (who may hold none of these bits themselves) must not be
  # able to point the bot at a role that would let it grant Administrator, ban,
  # kick, or manage roles/guild/channels. Discord permits granting such a role
  # as long as it sits below the bot's own, so filtering here is the guard that
  # keeps the web surface from crossing Discord's own permission boundary.
  module Permissions
    ADMINISTRATOR   = 1 << 3   # 0x8
    KICK_MEMBERS    = 1 << 1   # 0x2
    BAN_MEMBERS     = 1 << 2   # 0x4
    MANAGE_CHANNELS = 1 << 4   # 0x10
    MANAGE_GUILD    = 1 << 5   # 0x20
    MANAGE_ROLES    = 1 << 28  # 0x10000000

    # Any of these makes a role too dangerous to hand out from the web pickers.
    # ADMINISTRATOR implies all of them, but Discord does NOT expand it in the
    # bitfield, so it's listed explicitly rather than relied on.
    DANGEROUS_MASK = ADMINISTRATOR | KICK_MEMBERS | BAN_MEMBERS |
                     MANAGE_CHANNELS | MANAGE_GUILD | MANAGE_ROLES

    # `role["permissions"]` is a decimal string ("268435456"); nil/blank/zero
    # all read as "no dangerous bits". Anything that fails to parse is treated
    # as dangerous (fail closed).
    def self.dangerous_role?(role)
      raw = role["permissions"]
      return false if raw.nil? || raw.to_s.strip.empty?

      begin
        perms = Integer(raw.to_s.strip, 10)
      rescue ArgumentError
        return true
      end
      (perms & DANGEROUS_MASK) != 0
    end
  end
end
