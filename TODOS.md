# TODOs

**The working split:** *gathering* data is active work; *using* it is a TODO.
Anything that pulls a new fact into the database gets built now. Anything that
surfaces, judges, gates or acts on that data gets written down here until the
gathering is finished. Keeping the two apart stops half-built features from
dictating what the schema looks like.

Not a wishlist — only work that's been thought about and parked, with the
reasoning that parked it, so the thinking isn't lost.

---

# Gathering — unfinished

## 1. Blizzard guild roster reconciliation — needs a design decision first

**What it would do.** Blizzard's Game Data API exposes a guild's full in-game
roster (`/data/wow/guild/{realm}/{guild}/roster`) on the app's
client-credentials token — no user OAuth, no per-member consent. Compared
against a team's members it would spot people who have gquit, transferred, or
been removed in-game.

**Why it isn't built.** *co-bot teams do not require in-game guild membership.*
Membership is a Discord concept here: a team is a Discord role plus an
application flow, and plenty of legitimate members are in a different in-game
guild, on a different realm, or playing an alt that isn't guilded at all.
Treating "absent from the guild roster" as "should be removed from the team"
would be wrong for real people, and role removal is annoying to undo and
alarming to receive.

**What has to be decided first:**

- **Is guild membership expected per team?** Probably a per-team setting, off by
  default, plus which guild/realm — one co-bot Guild may host teams from several
  in-game guilds.
- **Which character counts?** A member may have linked five characters, one of
  which is guilded. "In the guild" should almost certainly mean *any* linked
  character, not their main.
- **What happens on a mismatch?** Strong preference for **notify, never act**.
  This must not become a second, silently-diverging source of truth alongside
  `Memberships::RoleSync`.
- **What about unlinked members?** Someone who has never linked Battle.net can't
  be reconciled at all and must not be reported as missing. "Unknown" is the
  common case and has to read as unknown.

`BattleNet::Client.app#guild_roster` already exists. Note this is the one
gathering task gated on a *product* decision rather than on access.

## 2. wowaudit — verify against a live key, then raids/attendance

Auth and the roster shape are settled (`Authorization: <raw key>`, confirmed
against wowaudit's own engine and two third-party clients), and
`WowAudit::SyncRoster` is built and tested. Still unverified against a real key,
because wowaudit's 401 is identical for a wrong, malformed, or absent key:

```bash
bin/rails co_bot:wowaudit_probe KEY=<a real key>   # dumps shapes, never values
```

**Then: raid signups and attendance.** `GET /v1/raids?include_past=true` returns
`{raids: [{id, date, instance, difficulty, present_size, total_size}]}` and
`GET /v1/raids/:id` adds `signups[].character` and
`encounters[].selections[]`. That's real attendance data and worth gathering —
deliberately left until the roster sync is confirmed against a live key, so one
verified shape lands before another is built on top of it. How it relates to
co-bot's existing `Absence` model is a *using* question and belongs below.

## 3. Equipment, Great Vault, talents — deferred to wowaudit by decision

**Decided: not building these.** Character-level gear auditing (enchants, gems,
sockets, Great Vault progress, talent loadouts) stays wowaudit's job. co-bot
integrates with wowaudit for team management and lets it own character
management.

Recorded here because the research is done and the decision could be revisited:
everything above **is** obtainable from Blizzard on the app token, and wowaudit
has no privileged access. Reading their open-source engine
(`github.com/wowaudit/core`) settled it — `Wowaudit::Client` has five retrievers
(blizzard, keystones, historical_keystones, wcl, raiderio) and authenticates
with a Blizzard client-credentials pair via `RBattlenet`. No addon upload path,
no user token.

The one non-obvious mechanism, if this is ever picked up: **Blizzard exposes no
Great Vault endpoint and wowaudit doesn't use one.** They derive it —
`/achievements/statistics` stamps every boss and dungeon with a `quantity` and a
`last_updated_timestamp`, so anything updated after the weekly reset was killed
this week, which is exactly what fills vault slots. M+ slots come from
`mythic-keystone-profile` `best_runs[].completed_timestamp` bucketed by period.
Verified: 486 boss statistics on one live character.
`BattleNet::Client#character_achievement_statistics` is already wired for it.

**Professions and the recipe catalog were split out of this and built.**

## 4. Per-boss Warcraft Logs parses

`warcraft_logs_rankings` stores the tier-level summary. The same response
carries a per-encounter `rankings` array (per-boss percentile, best amount,
fastest kill), supporting "show me their Mythic Fyrakk parse". Left out to avoid
sprawling the schema before the tier-level numbers are verified; `WowEncounter`
already gives it somewhere to hang.

## 5. murlok.io — probably a deep link, not an integration

Investigated at the PvP leads' suggestion. **It is a meta/build aggregator, not
a player database**: per class+spec+bracket it publishes stat priority, talents,
PvP talents, BiS gear, embellishments, enchants, gems and races, derived from
the top 50 players per spec and refreshed every 8 hours. It answers "what should
a Frost Mage be running in 3v3", not "how good is this applicant" — a different
category from every other integration here, which gather per-player facts.

It does have an API (`/api/`, `/api/v1`, `/api/rankings`) but every route
answers **401** with no public documentation, so it is not usable without
credentials from them.

The realistic integration needs no API at all: the URLs are predictable
(`murlok.io/{class}/{spec}/{bracket}`, e.g. `/mage/frost/3v3`), so once a
character's spec and bracket are known — both of which are now gathered — a deep
link to the current meta build is free. Worth doing when there's a surface to
put it on; not worth chasing API access for.

---

# Using — parked until gathering is done

## 6. Discord Linked Roles

The highest-leverage use of everything gathered, and the one that fits co-bot's
existing purpose best — but it's a *Discord-side* feature, so it waits.

An app registers up to five role-connection metadata fields; server admins then
build roles on them ("M+ ≥ 2500", "ilvl ≥ 640", "AOTC", "median parse ≥ 75") and
**Discord enforces the gate natively** — assignment, revocation, and the
member-facing UI, with no sweep or reconcile loop of ours.

- Needs the `role_connections.write` scope on the existing Discord OAuth, a
  metadata schema, and a push on each character refresh.
- **Five fields, app-wide, not per guild.** Which five is a product decision and
  the main thing to think about.
- Cheap cousin: gate on *"has Battle.net linked at all"* using the `connections`
  scope already in place — near-zero work, useful as an anti-alt signal.

## 7. Application review integration

Surface an applicant's record next to their answers: role, ilvl, current and
peak M+ score, season history, raid progression, parses. One query from a
`TeamMembership` today.

Open questions: how much belongs in the Discord review message versus the web
team page; whether unlinked applicants get a "link your account" prompt in the
apply flow; and whether any of it should be *automatic* (flagging an applicant
below a team's threshold) or purely informational. Leaning informational —
`Applications::Decide` is a human decision and should stay one.

## 8. Attendance from wowaudit vs. co-bot absences

co-bot already has absence call-outs (`Absence`, `AbsenceDigest`). wowaudit has
actual raid attendance. Reconciling them would show who called out versus who
simply didn't turn up — genuinely useful to a raid lead, and genuinely easy to
get wrong. Needs the wowaudit raid data gathered first (#3), then a real think
about whether co-bot should ever surface "no-showed" about a person.

## 9. WoW Token price alerts

The price series is being recorded now (`WowTokenPrice`, hourly). Using it — a
`/wow token` command showing the current price and weekly change, or a channel
post when it moves sharply — is a use, so it waits. `#change_since` and
`.format_change` are already there for whenever it happens.

## 10. Character showcase / roster board

A team roster view showing every member's best character with ilvl, score, role
and parse — the "who's actually on this team and how geared are they" board.
Overlaps with the existing `/team roster` directory; would need thought about
whether it extends that or is a separate web-only view.
