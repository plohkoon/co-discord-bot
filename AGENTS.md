# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**co-bot** is a modular Discord server-management bot **plus a first-class Rails web app**, sharing one database. It is multi-guild by design — never hardcode guild IDs; every guild-owned table is scoped by `guild_id`. The first (and currently only) module is **team management**: admins create teams, applicants `/apply` via a Discord modal, officers accept/reject with persistent buttons, and the bot auto-assigns team roles. The web app lets members log in with Discord to manage the same teams, questions, applications, and notes.

Rails 8, Ruby 3.4.1, discordrb 3.8, SQLite (WAL), Solid Queue, ViewComponent + Tailwind v4, `acts_as_tenant`.

## Commands

```bash
bin/setup                 # install gems + prepare DB (add --skip-server to not boot)
bin/dev                   # foreman: web (bin/rails server) + tailwind watch + bin/bot + bin/jobs
bin/rails server          # web only
bin/bot                   # Discord gateway only (standalone, boots full Rails env)

bin/rails db:prepare      # create + migrate
bin/rails db:test:prepare # sync test schema

bin/rails test                                  # unit/integration tests
bin/rails test test/models/team_test.rb         # single file
bin/rails test test/models/team_test.rb:42      # single test at a line
bin/rails test:system                           # Capybara system tests

bin/rubocop               # lint (rubocop-rails-omakase house style)
bin/brakeman --no-pager   # Rails security scan (runs in CI)
bin/bundler-audit         # gem CVE scan (runs in CI)
```

CI (`.github/workflows/ci.yml`) runs brakeman, bundler-audit, importmap audit, rubocop, `test`, and `test:system`.

Environment: copy `.env.example` → `.env`. Needs `DISCORD_BOT_TOKEN` (with **Server Members Intent** enabled in the portal) and `DISCORD_CLIENT_ID/SECRET` for web OAuth — from a **dev-only Discord application**; production uses a separate app whose credentials live in Fly secrets (a shared token would deliver gateway events to both environments). Commands register per guild on join. `bin/bot` idles gracefully when the token is missing, so `bin/dev` won't crash-loop before credentials exist.

## Architecture

### One process, three concerns

In development, `bin/dev` runs web, CSS watch, bot, and jobs (`bin/jobs`) as **separate Procfile processes**; jobs go through Solid Queue in dev too (own SQLite queue DB), matching production. In production, set `RUN_DISCORD_BOT=1` and `SOLID_QUEUE_IN_PUMA=1` (both in fly.toml) and `bin/rails server` boots everything in one unit: `config/puma.rb` loads `plugin :discord_bot` (`lib/puma/plugin/discord_bot.rb`), which **forks a supervised child** running the gateway — mirroring how Solid Queue's Puma plugin forks. The child gets its own AR connection pool (it clears inherited connections on fork), and the plugin ties the child's lifecycle to Puma's: if either dies, both come down so the process manager restarts the whole unit.

**The bot and web app never share in-process state** — they communicate only through the shared DB (and Solid Queue jobs). This is deliberate; keep it that way.

### Multi-tenancy (`acts_as_tenant`)

The tenant is `Guild` (its PK **is** the Discord snowflake). Guild-scoped models include the `GuildScoped` concern (`acts_as_tenant(:guild)`), so queries auto-scope and `guild_id` auto-fills on create. The current tenant is set at exactly **two entry points**:

- Web: a `before_action` in `app/controllers/concerns/guild_scoping.rb` wraps requests in `ActsAsTenant.with_tenant(@guild)`.
- Bot: `CoBot::Runner#with_tenant` wraps every dispatch in `ActsAsTenant.with_tenant(guild) { ... }`.

Background jobs/services that run outside a request (e.g. `Memberships::RoleSync`) must set the tenant themselves with `ActsAsTenant.with_tenant(guild) { ... }`.

### The bot layer (`app/bot/`)

- **`CoBot::Runner`** (`app/bot/co_bot/runner.rb`) owns the single `Discordrb::Bot`, installs signal traps, and runs the supervised restart-with-backoff loop (`run_supervised`). discordrb dispatches each gateway event on its own bare thread, so **every handler body must run inside `Rails.application.executor.wrap`** — `Runner.handle` does this; do not skip it or you leak AR connections.
- **Commands = one class per command, namespace = Discord path.** `Commands::Team::Member::Accept` → `/team member accept`. Base is `Commands::Base` (`app/bot/commands/base.rb`). Each class colocates: its option DSL (`string`/`role`/`channel`/… with `required:`/`autocomplete:`), permission gate (`admin_only!` / `officer_only!`, **enforced in-handler** because Discord's `default_member_permissions` is per-command and `/team` mixes access levels), `autocomplete_<option>(query)` resolvers, and a single-ack response API (`respond` / `show_modal` / `update_message` — each interaction may be answered exactly once; `ack!` guards double-answers).
- **Components** (persistent buttons/modals) are `Commands::Components::*` classes declaring `component :button/:modal, "key", params: [...]`. Their custom_ids survive bot restarts.
- **Manifest = `config/commands.rb`** via `CoBot::CommandRegistry.draw`. A single nested `command` keyword builds the tree (a `command` with children = subcommand group, without = leaf — no separate group/subcommand keywords, like Rails routes). **Each leaf's class is auto-discovered from its path**; pass `class:` only to override. `CommandRegistry` (`app/bot/co_bot/command_registry.rb`) turns the manifest into Discord registration, a `path → class` dispatch table, and autocomplete lookup. On sync it upserts each top-level command and **prunes any guild command no longer in the manifest**.
- **Discord constraint:** max 2 nesting levels, and options always trail the leaf subcommand. Current surface: `/team create|list|apply|edit|roster` + `/team member accept|reject|note|remove` + `/team category|type add|edit|remove` (admin; manage the curated roster lists).
- **Message actions = automatic responses to ordinary messages**, mirroring the command layer: one class per action in `app/bot/message_actions/` (base declares `match word:/contains:/pattern:` + `perform`), listed in the **`config/message_actions.rb`** manifest via `CoBot::MessageActionRegistry.draw` with path-discovered classes. The runner's `dispatch_message` skips bot authors and DMs, matches content **before** any DB work, then runs matching actions inside the tenant. Requires the **Message Content privileged intent** (portal toggle on both dev and prod apps) — discordrb 3.8 predates it, so `Runner::MESSAGE_CONTENT_INTENT` passes the raw bit.

### Domain model

`TeamMembership` is the durable person×team anchor (not the application): status `pending|active|archived`, `has_many :team_applications` (dated events) and `:membership_notes`. `TeamApplication` belongs to a membership with a `source` enum (`applied` via /apply, `manual` when a role is granted directly). State machine: apply → pending; accept or manual role grant → active; reject / role removed / member leaves → archived; re-apply on archived → pending. Role auto-sync uses the **Server Members privileged intent**: a `member_update` listener reconciles each team's role membership; `member_leave` archives. `Memberships::Backfill` sweeps existing role holders into a new team: `/team create` enqueues `TeamBackfillJob` (Solid Queue), which pages members over REST (`BotApi#each_guild_member` — no gateway needed) and reports the count via an interaction-token follow-up (`BotApi#interaction_followup`, valid ~15 min after the ack; best-effort). `Memberships::RoleManager` is the hierarchy-safe grant/revoke shared by buttons and commands (the bot needs Manage Roles **above** the team role).

`ApplicationQuestion` makes application questions configurable per team (Discord modal caps at 5 inputs).

**Team roster/directory:** teams carry free-form roster details (`Team::ROSTER_FIELDS`: emote — decorates the heading before the role mention; accepts unicode, `:name:` (normalized to `<:name:id>` by `Discord::EmoteResolver` against the guild's emoji list, since bots must post the full mention form), or a raw mention — plus the progression, requirements, date_and_time, current_needs lines). **Every free-typed field** (team/category/type names + the roster lines, both surfaces) gets lenient inline resolution at save time (`EmoteResolver.resolve_text`: known `:name:` shortcodes → mentions, unknown ones stay as typed — free text legitimately contains colons); only the standalone emote field is strict (unknown `:name:` rejects the save), a `position` (sort order within category), an optional `TeamCategory` (directory section header), and an optional `TeamType` (the "type" roster line, e.g. "Heroic Team"). **Categories and team types are curated per-guild lists** — teams pick from them (`.named` is a lookup, never a create): manage them via `/team category|type add|edit|remove` (admin) or the guild page's "Roster settings" section (Manage Server); `TeamType::DEFAULT_NAMES` (Normal/Heroic/Mythic/PvP Team) is seeded by `Guild.sync_from_discord` for new guilds. Teams can be renamed (`/team edit name:` — officer-level — or the web team form). Set roster details via `/team create|edit` options, the web team page, or the web **New team** form (`teams#new/create` — role/channel pickers fetched over REST and submitted ids validated against those lists; Manage Server comes free via `GuildScoping`; creation enqueues the same `TeamBackfillJob`). `/team roster` (admin) posts the directory as **Components-V2 messages** (`CoBot::RosterMessage` builds raw payloads — discordrb 3.8 predates V2 — sent over REST via `BotApi`): one seamless message with `## Category` headers and **one container per team whose accent border is the team role's live color**, each holding a section with the team block and its Apply button inline as the accessory (`Components::ApplyButton`, same modal flow as `/team apply` via shared `Commands::ApplyFlow`). Budgets: 40 components / 4000 text chars per message — `payloads` chunks and re-states headers when overflowing. Mentions never ping. Teams record roster_channel_id/message_id at post time (several teams usually share one message); anything that changes what the roster shows — team create (via `TeamBackfillJob`'s tail, after officers are seeded), team edit/rename (bot or web), category or team-type edits/removals (bot or web), officer-role changes — enqueues `RosterRefreshJob`, which **reflows the whole directory**: rebuilds payloads from all active teams, edits existing messages in place, posts extras when it grew, deletes leftovers when it shrank (hand-deleted messages are reposted; a vanished channel clears all stored ids). No-op until `/team roster` is first posted.

**Officers mirror (`team_officers`):** who holds each team's officer role, kept locally so nothing pages the guild member list at render time. Maintained by `RoleSync.sync_officer` on every `member_update` (and cleared on `member_leave`), seeded + pruned by `Memberships::Backfill` at team creation — Backfill's single member-pagination pass is the **only** full member scan in the app. The roster's "Team Leads" line reads this table; live-role checks are still used for authorization (`officer_for?`).

**Pending-application lifecycle:** one pending application per person×team, enforced three deep (the `/team apply` pre-check, `Applications::Submit`'s `DuplicatePending`, and a partial unique index). `Applications::Timeline` schedules exact-timestamp Solid Queue jobs at submit time — officer reminders at 24h/3d/6d and auto-reject at 7 days — and every handler short-circuits if the application was decided (`Decide`'s row-lock claim wins races). `team_applications.reminder_stage` records what's been sent; overdue jobs firing together after worker downtime collapse into one reminder ("only the latest due stage sends"). Auto-reject goes through the same `Decide` path as the buttons — `decided_by_discord_id: nil` means the system decided — and repaints the review message over REST. The queue DB is therefore durable business state, not just plumbing: dropping it drops the timers.

**Guild install-state reconciliation:** `Guild#removed_at` marks servers the bot was kicked from — rows (and team data) are never deleted, so re-inviting restores everything. It's stamped by the `server_delete` handler, by `sync_all_guilds` on every `ready` (two-way: upserts present guilds, marks missing ones), and by `Discord::GuildHealth` on a REST 404; it's cleared by any `Guild.sync_from_discord`. Web treats removed guilds as not installed (`Guild.installed` scope, blocked in `GuildScoping`) and the dashboard shows a re-invite card. `Discord::GuildHealth` (web-side REST via `Discord::BotApi` with the bot token, cached 60s) powers the permission-warning banner on the guild page — it mirrors the invariants `Memberships::RoleManager` enforces at action time.

**Install wizard:** `Discord::ManageableGuilds` partitions the user's Manage-Server guilds at login into `manageable` (Guild row exists — ids in the session) and `installable` (no row — full `{id,name,icon}` stored in `users.installable_guilds`, JSON-serialized, since the cookie is size-capped and there's no Guild row for names). The dashboard renders installable servers as "Add co-bot" cards linking to `discord_install_url` (helper owns `BOT_INVITE_PERMISSIONS`; the URL's `permissions` param overrides any portal defaults). A Stimulus `install-poll` controller polls `GET /install_status` and reloads when the bot's `server_create` lands the Guild row; `ApplicationController#manageable_guild_ids` auto-promotes installable ids whose row now exists (Manage Server was verified at login), so no re-login is needed after an install.

Business logic lives in `app/services/` (e.g. `Applications::Submit`, `Applications::Decide`, `Memberships::Activate/Archive/RoleSync/RoleManager`), not in commands or controllers.

### Web UI (ViewComponent design system)

**Web access tiers** (per guild, enforced by `GuildScoping`): *viewing* a server needs only membership — `Discord::ManageableGuilds` captures every known guild the user belongs to at login (`session[:member_guild_ids]`), and the `team_officers` mirror grants view access to team leads even when their session predates the role. *Opening a team page* needs Manage Server or a lead (officer) of that team (`require_team_access`; leads get the full officer toolkit mirroring Discord — memberships, notes, accept/reject via `ApplicationDecisionsController` → `Applications::Decide`, member removal via `memberships#remove` → `Memberships::RestRoleManager` + `Archive`, and editing the team's details via `teams#update`, mirroring the officer-level `/team edit`). **Position is the exception**: directory placement relative to other teams is Manage Server only on both surfaces — the bot handler rejects it for non-admins, the web strips the param and hides the field. *Team settings* — create, questions, health recheck, the curated category/type lists — need Manage Server (`require_guild_manager`), matching the bot's admin-only commands. Views branch on the `can_manage?` / `officer_of?(team)` helpers.

Components in `app/components/`: base `ApplicationComponent`, a `Ui::` kit (`Card/Button/Badge/Avatar/StatTile/EmptyState/Section/PageHeader`), and top-level `StatusBadgeComponent`. Views compose these; form fields use the `.field` CSS class, and `Ui::ButtonComponent.classes(variant:, size:)` styles bare `button_to`/submits. Theme is shadcn-style CSS-variable tokens on a warm charcoal base with a **gold `#FFD166`** accent, in `app/assets/tailwind/application.css` (Tailwind v4, `@source` scans components + views). **Dark-only.** Login is Discord OAuth2 via `omniauth-discord`.

**Admin panel (`/admin`):** app-wide, cross-tenant, gated by the hardcoded `User::ADMIN_DISCORD_IDS` allowlist (`Admin::BaseController#require_admin`; admin cannot be granted through the app). Two generic catch-all routes (`/admin/:model`, `/admin/:model/:id`) drive a reflection-based read-only browser over every `ApplicationRecord` model (`Admin::ResourcesController` — queries run `ActsAsTenant.without_tenant`; add future secret columns to its `HIDDEN_COLUMNS`). `/admin/jobs` is the Solid Queue dashboard (`Admin::JobsController`): tabs for all/failed/scheduled/recurring/processes, retry/discard (single + bulk) on failed executions. Test env has its own queue DB so these pages are testable; `test_helper`'s `sign_in_as(user)` logs in through the OmniAuth callback with the Discord guild fetch stubbed.

## Conventions & gotchas

- **Never do Discord/network I/O inside a DB transaction.** Keep write transactions short.
- **SQLite is intentional.** Keep the schema portable (integer PKs, `t.text` for free-form) so a later Postgres switch stays a config change. Litestream handles off-host backups.
- Guild snowflakes and other Discord IDs exceed 32-bit; store them as `bigint`/`t.text`, never assume they fit an `int`.
- discordrb: start with `bot.run(true)` (positional async flag, **not** `async:`), stop with `bot.stop`.
