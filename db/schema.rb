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

ActiveRecord::Schema[8.1].define(version: 2026_04_04_151309) do
  create_table "documentation", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path", null: false
    t.json "metadata", default: {}
    t.datetime "updated_at", null: false
    t.index ["file_path"], name: "index_documentation_on_file_path", unique: true
  end

  create_table "media", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_path"
    t.string "media_type"
    t.datetime "updated_at", null: false
    t.datetime "uploaded_at"
    t.index ["file_path"], name: "index_media_on_file_path", unique: true
  end

  create_table "media_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "medium_id", null: false
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.index ["medium_id"], name: "index_media_references_on_medium_id"
    t.index ["post_id", "medium_id"], name: "index_media_references_on_post_id_and_medium_id", unique: true
    t.index ["post_id"], name: "index_media_references_on_post_id"
  end

  create_table "members", force: :cascade do |t|
    t.string "access_token", limit: 36, null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.json "metadata", default: {}
    t.string "name"
    t.datetime "paid_at"
    t.string "password_digest"
    t.integer "status", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_payment_intent_id"
    t.datetime "subscribed_at"
    t.integer "tier", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["access_token"], name: "index_members_on_access_token", unique: true
    t.index ["email"], name: "index_members_on_email", unique: true
    t.index ["status"], name: "index_members_on_status"
    t.index ["stripe_customer_id"], name: "index_members_on_stripe_customer_id", unique: true
    t.index ["tier", "status"], name: "index_members_on_tier_and_status"
  end

  create_table "pages", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path"
    t.json "metadata"
    t.datetime "updated_at", null: false
  end

  create_table "posts", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path"
    t.json "metadata", default: {}
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "site_configs", force: :cascade do |t|
    t.json "config", default: {}
    t.datetime "created_at", null: false
    t.string "file_path", null: false
    t.datetime "updated_at", null: false
    t.index ["file_path"], name: "index_site_configs_on_file_path", unique: true
  end

  create_table "stripe_configs", force: :cascade do |t|
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.string "currency"
    t.integer "mode", default: 0, null: false
    t.string "price_id"
    t.string "product_id"
    t.text "publishable_key_live"
    t.text "publishable_key_test"
    t.text "secret_key_live"
    t.text "secret_key_test"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "media_references", "media"
  add_foreign_key "media_references", "posts"
  add_foreign_key "sessions", "users"
end
