# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_27_260000) do
  create_table "absence_digests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "digest_on", null: false
    t.bigint "guild_id", null: false
    t.bigint "lead_channel_id"
    t.bigint "lead_message_id"
    t.datetime "sent_at"
    t.integer "status", default: 0, null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_absence_digests_on_guild_id"
    t.index ["team_id", "digest_on"], name: "index_absence_digests_on_team_id_and_digest_on", unique: true
  end

  create_table "absences", force: :cascade do |t|
    t.date "absence_on", null: false
    t.datetime "cancelled_at"
    t.bigint "cancelled_by_discord_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_discord_id", null: false
    t.bigint "discord_user_id", null: false
    t.string "discord_username", default: "", null: false
    t.bigint "guild_id", null: false
    t.text "note"
    t.integer "status", default: 0, null: false
    t.integer "team_id", null: false
    t.integer "team_membership_id"
    t.datetime "updated_at", null: false
    t.index ["discord_user_id", "absence_on"], name: "index_absences_on_discord_user_id_and_absence_on"
    t.index ["guild_id"], name: "index_absences_on_guild_id"
    t.index ["team_id", "absence_on"], name: "index_absences_on_team_id_and_absence_on"
    t.index ["team_id", "discord_user_id", "absence_on"], name: "index_absences_one_active_per_user_team_day", unique: true, where: "status = 0"
    t.index ["team_id"], name: "index_absences_on_team_id"
  end

  create_table "application_answers", force: :cascade do |t|
    t.text "answer", default: "", null: false
    t.datetime "created_at", null: false
    t.bigint "guild_id", null: false
    t.integer "position", default: 0, null: false
    t.string "question_key", null: false
    t.string "question_label", null: false
    t.integer "team_application_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_application_id", "position"], name: "index_application_answers_on_team_application_id_and_position"
    t.index ["team_application_id"], name: "index_application_answers_on_team_application_id"
  end

  create_table "application_questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "guild_id", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.integer "max_length"
    t.integer "min_length"
    t.string "placeholder"
    t.integer "position", default: 0, null: false
    t.boolean "required", default: true, null: false
    t.integer "style", default: 0, null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_application_questions_on_guild_id"
    t.index ["team_id", "key"], name: "index_application_questions_on_team_id_and_key", unique: true
    t.index ["team_id", "position"], name: "index_application_questions_on_team_id_and_position"
    t.index ["team_id"], name: "index_application_questions_on_team_id"
  end

  create_table "battle_net_accounts", force: :cascade do |t|
    t.bigint "battle_net_id", null: false
    t.string "battle_tag"
    t.datetime "characters_synced_at"
    t.datetime "created_at", null: false
    t.datetime "linked_at", null: false
    t.string "region", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["battle_net_id"], name: "index_battle_net_accounts_on_battle_net_id"
    t.index ["user_id", "battle_net_id"], name: "index_battle_net_accounts_on_user_id_and_battle_net_id", unique: true
    t.index ["user_id"], name: "index_battle_net_accounts_on_user_id"
  end

  create_table "guilds", id: false, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "id", null: false
    t.bigint "important_log_channel_id"
    t.bigint "log_channel_id"
    t.string "name", default: "", null: false
    t.datetime "removed_at"
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["id"], name: "index_guilds_on_id", unique: true
  end

  create_table "membership_notes", force: :cascade do |t|
    t.bigint "author_discord_id", null: false
    t.string "author_username", default: "", null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.bigint "guild_id", null: false
    t.integer "team_membership_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_membership_notes_on_guild_id"
    t.index ["team_membership_id"], name: "index_membership_notes_on_team_membership_id"
  end

  create_table "team_applications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.bigint "decided_by_discord_id"
    t.bigint "discord_user_id", null: false
    t.string "discord_username", default: "", null: false
    t.bigint "guild_id", null: false
    t.datetime "paused_at"
    t.bigint "paused_by_discord_id"
    t.bigint "review_channel_id"
    t.bigint "review_message_id"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "team_id", null: false
    t.integer "team_membership_id"
    t.datetime "timeline_started_at"
    t.datetime "updated_at", null: false
    t.index ["discord_user_id"], name: "index_team_applications_on_discord_user_id"
    t.index ["guild_id"], name: "index_team_applications_on_guild_id"
    t.index ["team_id", "discord_user_id", "status"], name: "idx_on_team_id_discord_user_id_status_801561e00c"
    t.index ["team_id", "discord_user_id"], name: "index_team_applications_one_pending_per_user", unique: true, where: "status = 0"
    t.index ["team_id"], name: "index_team_applications_on_team_id"
    t.index ["team_membership_id"], name: "index_team_applications_on_team_membership_id"
  end

  create_table "team_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "guild_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "name"], name: "index_team_categories_on_guild_id_and_name", unique: true
    t.index ["guild_id"], name: "index_team_categories_on_guild_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "discord_user_id", null: false
    t.string "discord_username", default: "", null: false
    t.bigint "guild_id", null: false
    t.datetime "joined_at"
    t.datetime "left_at"
    t.integer "status", default: 0, null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_team_memberships_on_guild_id"
    t.index ["team_id", "discord_user_id"], name: "index_team_memberships_on_team_id_and_discord_user_id", unique: true
    t.index ["team_id", "status"], name: "index_team_memberships_on_team_id_and_status"
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
  end

  create_table "team_officers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "discord_user_id", null: false
    t.string "discord_username", default: "", null: false
    t.bigint "guild_id", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_team_officers_on_guild_id"
    t.index ["team_id", "discord_user_id"], name: "index_team_officers_on_team_id_and_discord_user_id", unique: true
  end

  create_table "team_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "guild_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "name"], name: "index_team_types_on_guild_id_and_name", unique: true
    t.index ["guild_id"], name: "index_team_types_on_guild_id"
  end

  create_table "teams", force: :cascade do |t|
    t.text "absence_response"
    t.boolean "active", default: true, null: false
    t.text "apply_response"
    t.text "closed_message"
    t.datetime "created_at", null: false
    t.text "current_needs"
    t.text "date_and_time"
    t.text "description"
    t.string "emote"
    t.bigint "guild_id", null: false
    t.bigint "last_review_digest_message_id"
    t.date "last_review_digest_on"
    t.string "name", null: false
    t.bigint "officer_role_id", null: false
    t.integer "position", default: 0, null: false
    t.text "progression"
    t.boolean "recruiting", default: true, null: false
    t.boolean "remind_ping", default: true, null: false
    t.text "requirements"
    t.bigint "review_channel_id", null: false
    t.boolean "review_digest", default: true, null: false
    t.integer "review_digest_after_days", default: 1, null: false
    t.bigint "roster_channel_id"
    t.bigint "roster_message_id"
    t.integer "team_category_id"
    t.bigint "team_role_id", null: false
    t.integer "team_type_id"
    t.datetime "updated_at", null: false
    t.string "wowaudit_api_key"
    t.string "wowaudit_team_name"
    t.datetime "wowaudit_verified_at"
    t.index ["guild_id", "name"], name: "index_teams_on_guild_id_and_name", unique: true
    t.index ["guild_id"], name: "index_teams_on_guild_id"
    t.index ["team_category_id"], name: "index_teams_on_team_category_id"
    t.index ["team_type_id"], name: "index_teams_on_team_type_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "authenticated_at"
    t.string "avatar"
    t.datetime "created_at", null: false
    t.string "discord_battle_net_id"
    t.string "discord_battle_tag"
    t.bigint "discord_id", null: false
    t.string "global_name"
    t.text "installable_guilds"
    t.datetime "updated_at", null: false
    t.string "username", default: "", null: false
    t.index ["discord_id"], name: "index_users_on_discord_id", unique: true
  end

  create_table "warcraft_logs_rankings", force: :cascade do |t|
    t.decimal "all_stars_points", precision: 10, scale: 2
    t.integer "all_stars_rank"
    t.integer "all_stars_rank_percent"
    t.decimal "best_performance_average", precision: 6, scale: 2
    t.datetime "created_at", null: false
    t.integer "difficulty", null: false
    t.datetime "fetched_at", null: false
    t.decimal "median_performance_average", precision: 6, scale: 2
    t.string "metric"
    t.string "spec_name"
    t.integer "total_kills"
    t.datetime "updated_at", null: false
    t.integer "wcl_zone_id", null: false
    t.integer "wow_character_id", null: false
    t.index ["wow_character_id", "wcl_zone_id", "difficulty"], name: "index_wcl_rankings_on_character_zone_difficulty", unique: true
    t.index ["wow_character_id"], name: "index_warcraft_logs_rankings_on_wow_character_id"
  end

  create_table "warcraft_logs_zones", force: :cascade do |t|
    t.boolean "closed", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "expansion_id"
    t.string "expansion_name"
    t.string "kind", default: "raid", null: false
    t.string "name"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.integer "wcl_id", null: false
    t.index ["closed", "expansion_id"], name: "index_warcraft_logs_zones_on_closed_and_expansion_id"
    t.index ["kind"], name: "index_warcraft_logs_zones_on_kind"
    t.index ["wcl_id"], name: "index_warcraft_logs_zones_on_wcl_id", unique: true
  end

  create_table "wow_character_achievements", force: :cascade do |t|
    t.bigint "blizzard_id", null: false
    t.string "category", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "wow_character_id", null: false
    t.index ["wow_character_id", "blizzard_id"], name: "idx_on_wow_character_id_blizzard_id_d5604c9dd7", unique: true
    t.index ["wow_character_id", "category"], name: "idx_on_wow_character_id_category_574307f2d2"
    t.index ["wow_character_id"], name: "index_wow_character_achievements_on_wow_character_id"
  end

  create_table "wow_character_profession_tiers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "known_recipe_count", default: 0
    t.integer "max_skill_points"
    t.string "name", null: false
    t.integer "skill_points"
    t.integer "tier_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wow_character_profession_id", null: false
    t.index ["wow_character_profession_id", "tier_id"], name: "index_profession_tiers_on_profession_and_tier", unique: true
    t.index ["wow_character_profession_id"], name: "index_profession_tiers_on_profession_id"
  end

  create_table "wow_character_professions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.integer "profession_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wow_character_id", null: false
    t.index ["name"], name: "index_wow_character_professions_on_name"
    t.index ["wow_character_id", "profession_id"], name: "idx_on_wow_character_id_profession_id_5a42f076e3", unique: true
    t.index ["wow_character_id"], name: "index_wow_character_professions_on_wow_character_id"
  end

  create_table "wow_character_pvp_ratings", force: :cascade do |t|
    t.string "bracket", null: false
    t.string "bracket_type", null: false
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.integer "lost", default: 0
    t.integer "played", default: 0
    t.integer "rating"
    t.integer "season_id", null: false
    t.string "spec_slug"
    t.integer "tier_id"
    t.datetime "updated_at", null: false
    t.integer "weekly_lost", default: 0
    t.integer "weekly_played", default: 0
    t.integer "weekly_won", default: 0
    t.integer "won", default: 0
    t.integer "wow_character_id", null: false
    t.index ["season_id", "bracket_type", "rating"], name: "idx_on_season_id_bracket_type_rating_7cc2935634"
    t.index ["wow_character_id", "season_id", "bracket"], name: "index_pvp_ratings_on_character_season_bracket", unique: true
    t.index ["wow_character_id"], name: "index_wow_character_pvp_ratings_on_wow_character_id"
  end

  create_table "wow_character_raids", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.integer "heroic_bosses_killed", default: 0
    t.integer "mythic_bosses_killed", default: 0
    t.integer "normal_bosses_killed", default: 0
    t.string "raid_slug", null: false
    t.string "summary"
    t.integer "total_bosses"
    t.datetime "updated_at", null: false
    t.integer "wow_character_id", null: false
    t.index ["wow_character_id", "raid_slug"], name: "index_wow_character_raids_on_wow_character_id_and_raid_slug", unique: true
    t.index ["wow_character_id"], name: "index_wow_character_raids_on_wow_character_id"
  end

  create_table "wow_character_recipes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wow_character_id", null: false
    t.index ["recipe_id"], name: "index_wow_character_recipes_on_recipe_id"
    t.index ["wow_character_id", "recipe_id"], name: "index_wow_character_recipes_on_wow_character_id_and_recipe_id", unique: true
    t.index ["wow_character_id"], name: "index_wow_character_recipes_on_wow_character_id"
  end

  create_table "wow_character_seasons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.decimal "score_all", precision: 7, scale: 1
    t.decimal "score_dps", precision: 7, scale: 1
    t.decimal "score_healer", precision: 7, scale: 1
    t.decimal "score_tank", precision: 7, scale: 1
    t.string "season_slug", null: false
    t.datetime "updated_at", null: false
    t.integer "wow_character_id", null: false
    t.index ["season_slug"], name: "index_wow_character_seasons_on_season_slug"
    t.index ["wow_character_id", "season_slug"], name: "idx_on_wow_character_id_season_slug_bfdce2c589", unique: true
    t.index ["wow_character_id"], name: "index_wow_character_seasons_on_wow_character_id"
  end

  create_table "wow_characters", force: :cascade do |t|
    t.datetime "achievements_refreshed_at"
    t.string "active_spec"
    t.integer "average_item_level"
    t.integer "battle_net_account_id"
    t.bigint "blizzard_id", null: false
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.string "faction"
    t.string "guild_name"
    t.integer "honor_level"
    t.bigint "honorable_kills"
    t.integer "item_level"
    t.datetime "last_login_at"
    t.integer "level"
    t.datetime "missing_at"
    t.decimal "mythic_rating", precision: 7, scale: 2
    t.string "name", null: false
    t.string "playable_class"
    t.string "playable_race"
    t.datetime "professions_refreshed_at"
    t.datetime "pvp_refreshed_at"
    t.datetime "raider_io_refreshed_at"
    t.string "raider_io_role"
    t.decimal "raider_io_score", precision: 7, scale: 1
    t.string "realm", null: false
    t.bigint "realm_id"
    t.string "realm_slug", null: false
    t.datetime "refreshed_at"
    t.string "region"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.datetime "verified_at"
    t.integer "warcraft_logs_id"
    t.datetime "warcraft_logs_missing_at"
    t.datetime "warcraft_logs_refreshed_at"
    t.index ["achievements_refreshed_at"], name: "index_wow_characters_on_achievements_refreshed_at"
    t.index ["battle_net_account_id"], name: "index_wow_characters_on_battle_net_account_id"
    t.index ["blizzard_id"], name: "index_wow_characters_on_blizzard_id", unique: true
    t.index ["raider_io_refreshed_at"], name: "index_wow_characters_on_raider_io_refreshed_at"
    t.index ["refreshed_at"], name: "index_wow_characters_on_refreshed_at"
    t.index ["user_id"], name: "index_wow_characters_on_user_id"
  end

  create_table "wow_encounters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "journal_id", null: false
    t.string "name"
    t.string "normalized_name"
    t.string "raid_slug"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.integer "wcl_zone_id"
    t.index ["journal_id"], name: "index_wow_encounters_on_journal_id", unique: true
    t.index ["normalized_name"], name: "index_wow_encounters_on_normalized_name"
    t.index ["raid_slug"], name: "index_wow_encounters_on_raid_slug"
    t.index ["wcl_zone_id"], name: "index_wow_encounters_on_wcl_zone_id"
  end

  create_table "wow_mythic_plus_cutoffs", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.string "faction", null: false
    t.decimal "min_score", precision: 8, scale: 2, null: false
    t.integer "population_count"
    t.decimal "quantile", precision: 6, scale: 5
    t.string "quantile_key", null: false
    t.string "region", null: false
    t.string "season_slug", null: false
    t.integer "total_population"
    t.datetime "updated_at", null: false
    t.index ["season_slug", "region", "faction", "quantile_key", "min_score"], name: "index_mplus_cutoffs_on_season_region_faction_key_score", unique: true
    t.index ["season_slug", "region", "quantile_key"], name: "idx_on_season_slug_region_quantile_key_b986ad4ef5"
  end

  create_table "wow_pvp_cutoffs", force: :cascade do |t|
    t.string "achievement_name"
    t.string "bracket_type", null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.integer "rating_cutoff", null: false
    t.integer "season_id", null: false
    t.integer "specialization_id"
    t.string "specialization_name"
    t.datetime "updated_at", null: false
    t.index ["season_id", "bracket_type", "specialization_id", "rating_cutoff"], name: "index_pvp_cutoffs_on_season_bracket_spec_rating", unique: true
  end

  create_table "wow_pvp_seasons", force: :cascade do |t|
    t.integer "blizzard_id", null: false
    t.datetime "created_at", null: false
    t.boolean "current", default: false, null: false
    t.string "name"
    t.datetime "starts_at"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id"], name: "index_wow_pvp_seasons_on_blizzard_id", unique: true
  end

  create_table "wow_pvp_tiers", force: :cascade do |t|
    t.integer "blizzard_id", null: false
    t.string "bracket_type"
    t.datetime "created_at", null: false
    t.integer "max_rating"
    t.integer "min_rating"
    t.string "name"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id"], name: "index_wow_pvp_tiers_on_blizzard_id", unique: true
  end

  create_table "wow_raids", force: :cascade do |t|
    t.integer "boss_count"
    t.datetime "created_at", null: false
    t.integer "expansion_id"
    t.string "name"
    t.string "short_name"
    t.string "slug", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_wow_raids_on_slug", unique: true
  end

  create_table "wow_recipes", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "profession_id"
    t.string "profession_name"
    t.bigint "recipe_id", null: false
    t.integer "skill_tier_id"
    t.string "skill_tier_name"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_wow_recipes_on_name"
    t.index ["profession_id"], name: "index_wow_recipes_on_profession_id"
    t.index ["recipe_id"], name: "index_wow_recipes_on_recipe_id", unique: true
    t.index ["skill_tier_id"], name: "index_wow_recipes_on_skill_tier_id"
  end

  create_table "wow_seasons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.integer "expansion_id"
    t.string "name"
    t.boolean "ranked", default: false, null: false
    t.string "short_name"
    t.string "slug", null: false
    t.datetime "starts_at"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["ranked", "ends_at"], name: "index_wow_seasons_on_ranked_and_ends_at"
    t.index ["slug"], name: "index_wow_seasons_on_slug", unique: true
  end

  create_table "wow_token_prices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "price", null: false
    t.datetime "recorded_at", null: false
    t.string "region", null: false
    t.datetime "updated_at", null: false
    t.index ["region", "recorded_at"], name: "index_wow_token_prices_on_region_and_recorded_at", unique: true
  end

  create_table "wowaudit_characters", force: :cascade do |t|
    t.string "character_class"
    t.datetime "created_at", null: false
    t.bigint "guild_id", null: false
    t.string "name", null: false
    t.string "realm"
    t.string "role"
    t.datetime "synced_at", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wow_character_id"
    t.integer "wowaudit_id", null: false
    t.index ["guild_id", "name"], name: "index_wowaudit_characters_on_guild_id_and_name"
    t.index ["guild_id"], name: "index_wowaudit_characters_on_guild_id"
    t.index ["team_id", "wowaudit_id"], name: "index_wowaudit_characters_on_team_id_and_wowaudit_id", unique: true
    t.index ["team_id"], name: "index_wowaudit_characters_on_team_id"
    t.index ["wow_character_id"], name: "index_wowaudit_characters_on_wow_character_id"
  end

  add_foreign_key "absence_digests", "guilds"
  add_foreign_key "absence_digests", "teams"
  add_foreign_key "absences", "guilds"
  add_foreign_key "absences", "team_memberships"
  add_foreign_key "absences", "teams"
  add_foreign_key "application_answers", "guilds"
  add_foreign_key "application_answers", "team_applications"
  add_foreign_key "application_questions", "guilds"
  add_foreign_key "application_questions", "teams"
  add_foreign_key "battle_net_accounts", "users"
  add_foreign_key "membership_notes", "guilds"
  add_foreign_key "membership_notes", "team_memberships"
  add_foreign_key "team_applications", "guilds"
  add_foreign_key "team_applications", "team_memberships"
  add_foreign_key "team_applications", "teams"
  add_foreign_key "team_categories", "guilds"
  add_foreign_key "team_memberships", "guilds"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_officers", "guilds"
  add_foreign_key "team_officers", "teams"
  add_foreign_key "team_types", "guilds"
  add_foreign_key "teams", "guilds"
  add_foreign_key "teams", "team_categories"
  add_foreign_key "teams", "team_types"
  add_foreign_key "warcraft_logs_rankings", "wow_characters"
  add_foreign_key "wow_character_achievements", "wow_characters"
  add_foreign_key "wow_character_profession_tiers", "wow_character_professions"
  add_foreign_key "wow_character_professions", "wow_characters"
  add_foreign_key "wow_character_pvp_ratings", "wow_characters"
  add_foreign_key "wow_character_raids", "wow_characters"
  add_foreign_key "wow_character_recipes", "wow_characters"
  add_foreign_key "wow_character_seasons", "wow_characters"
  add_foreign_key "wow_characters", "battle_net_accounts"
  add_foreign_key "wow_characters", "users"
  add_foreign_key "wowaudit_characters", "guilds"
  add_foreign_key "wowaudit_characters", "teams"
  add_foreign_key "wowaudit_characters", "wow_characters"
end
