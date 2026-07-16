# co-bot

A modular Discord server-management bot with a first-class Rails web app, sharing one database. Multi-guild by design — nothing is hardcoded to a single server. The first module is **team management**: admins create teams, applicants apply through a Discord modal, officers accept or reject with buttons that survive restarts, and the bot assigns team roles automatically. Members can also log in to the web app with Discord to manage teams, application questions, applications, and notes.

## Stack

- **Ruby** 3.4.1, **Rails** 8
- **discordrb** 3.8 for the Discord gateway
- **SQLite** (WAL) with Litestream for off-host backups
- **Solid Queue** for background jobs
- **acts_as_tenant** for per-guild multi-tenancy
- **ViewComponent** + **Tailwind CSS v4** for the web UI
- Discord OAuth2 login via **omniauth-discord**

## Getting started

```bash
bin/setup        # install gems and prepare the database
cp .env.example .env   # then fill in the values below
bin/dev          # run web + CSS watch + Discord bot together
```

The web app runs at http://localhost:3000.

### Configuration

Copy `.env.example` to `.env` and fill in:

- `DISCORD_BOT_TOKEN` — bot token from the Developer Portal. **Also enable the Server Members Intent** on the Bot page; co-bot uses it to auto-sync memberships when roles change.
- `DISCORD_CLIENT_ID` / `DISCORD_CLIENT_SECRET` — for web login. Add `http://localhost:3000/auth/discord/callback` as an OAuth2 redirect.
- `DISCORD_TEST_GUILD_ID` — your test server's ID. Slash commands register to this one guild instantly (global registration can take up to an hour).

The gateway idles gracefully when `DISCORD_BOT_TOKEN` is missing, so `bin/dev` won't crash-loop before credentials are set.

## Development

```bash
bin/dev                                    # web, CSS watch, and bot (foreman)
bin/rails server                           # web only
bin/bot                                    # Discord gateway only

bin/rails test                             # unit and integration tests
bin/rails test test/models/team_test.rb:42 # a single test
bin/rails test:system                      # Capybara system tests

bin/rubocop                                # lint
bin/brakeman --no-pager                    # Rails security scan
```

CI runs brakeman, bundler-audit, importmap audit, rubocop, and the full test suite.

## Architecture

In development the web app, CSS watcher, and Discord bot run as separate processes via `bin/dev`. In production, setting `RUN_DISCORD_BOT=1` makes `bin/rails server` boot everything as one unit — a Puma plugin forks the gateway as a supervised child process, so web, jobs, and bot start and stop together. The bot and web app never share in-process state; they communicate only through the shared database and Solid Queue jobs.

See [AGENTS.md](AGENTS.md) for a fuller architecture guide (command layer, tenancy, domain model, and conventions).
