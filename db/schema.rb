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

ActiveRecord::Schema[8.1].define(version: 2026_03_09_211708) do
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

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "sessions", "users"
end
