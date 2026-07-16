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

ActiveRecord::Schema[8.1].define(version: 2026_07_16_235222) do
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

  create_table "guilds", id: false, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "id", null: false
    t.string "name", default: "", null: false
    t.datetime "removed_at"
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
    t.integer "reminder_stage", default: 0, null: false
    t.bigint "review_channel_id"
    t.bigint "review_message_id"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "team_id", null: false
    t.integer "team_membership_id"
    t.datetime "updated_at", null: false
    t.index ["discord_user_id"], name: "index_team_applications_on_discord_user_id"
    t.index ["guild_id"], name: "index_team_applications_on_guild_id"
    t.index ["team_id", "discord_user_id", "status"], name: "idx_on_team_id_discord_user_id_status_801561e00c"
    t.index ["team_id", "discord_user_id"], name: "index_team_applications_one_pending_per_user", unique: true, where: "status = 0"
    t.index ["team_id"], name: "index_team_applications_on_team_id"
    t.index ["team_membership_id"], name: "index_team_applications_on_team_membership_id"
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

  create_table "teams", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "guild_id", null: false
    t.string "name", null: false
    t.bigint "officer_role_id", null: false
    t.bigint "review_channel_id", null: false
    t.bigint "team_role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "name"], name: "index_teams_on_guild_id_and_name", unique: true
    t.index ["guild_id"], name: "index_teams_on_guild_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar"
    t.datetime "created_at", null: false
    t.bigint "discord_id", null: false
    t.string "global_name"
    t.text "installable_guilds"
    t.datetime "updated_at", null: false
    t.string "username", default: "", null: false
    t.index ["discord_id"], name: "index_users_on_discord_id", unique: true
  end

  add_foreign_key "application_answers", "guilds"
  add_foreign_key "application_answers", "team_applications"
  add_foreign_key "application_questions", "guilds"
  add_foreign_key "application_questions", "teams"
  add_foreign_key "membership_notes", "guilds"
  add_foreign_key "membership_notes", "team_memberships"
  add_foreign_key "team_applications", "guilds"
  add_foreign_key "team_applications", "team_memberships"
  add_foreign_key "team_applications", "teams"
  add_foreign_key "team_memberships", "guilds"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "teams", "guilds"
end
