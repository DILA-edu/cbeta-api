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

ActiveRecord::Schema[8.1].define(version: 2026_08_21_110200) do
  create_table "api_key_usages", force: :cascade do |t|
    t.integer "api_key_id", null: false
    t.integer "count", default: 0, null: false
    t.date "used_on", null: false
    t.integer "user_id", null: false
    t.index ["api_key_id", "used_on"], name: "index_api_key_usages_on_api_key_id_and_used_on", unique: true
    t.index ["api_key_id"], name: "index_api_key_usages_on_api_key_id"
    t.index ["user_id", "used_on"], name: "index_api_key_usages_on_user_id_and_used_on"
    t.index ["user_id"], name: "index_api_key_usages_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_hint", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id", "revoked_at"], name: "index_api_keys_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end
end
