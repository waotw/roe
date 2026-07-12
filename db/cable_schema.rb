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

ActiveRecord::Schema[8.1].define(version: 2026_07_12_193832) do
  create_table "deploy_secrets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "registry_password"
    t.datetime "updated_at", null: false
  end

  create_table "disputes", force: :cascade do |t|
    t.integer "amount_cents"
    t.datetime "created_at", null: false
    t.string "currency"
    t.integer "status", default: 0, null: false
    t.string "stripe_charge_id"
    t.string "stripe_dispute_id", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_disputes_on_status"
    t.index ["stripe_dispute_id"], name: "index_disputes_on_stripe_dispute_id", unique: true
  end

  create_table "documentation", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path", null: false
    t.json "metadata", default: {}
    t.datetime "updated_at", null: false
    t.index ["file_path"], name: "index_documentation_on_file_path", unique: true
  end

  create_table "donations", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "email", null: false
    t.integer "member_id"
    t.integer "refunded_amount_cents"
    t.datetime "refunded_at"
    t.string "refunded_currency"
    t.string "stripe_payment_intent_id"
    t.string "stripe_session_id"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_donations_on_created_at"
    t.index ["email"], name: "index_donations_on_email"
    t.index ["member_id"], name: "index_donations_on_member_id"
    t.index ["stripe_session_id"], name: "index_donations_on_stripe_session_id", unique: true
  end

  create_table "imports", force: :cascade do |t|
    t.string "archive_file"
    t.datetime "completed_at"
    t.json "completed_phases", default: []
    t.json "configuration", default: {}
    t.datetime "created_at", null: false
    t.text "error_message"
    t.json "original_data", default: {}
    t.integer "phase", default: 1, null: false
    t.json "rss_data"
    t.string "source_type", default: "substack", null: false
    t.datetime "started_at"
    t.json "stats", default: {}
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_imports_on_created_at"
    t.index ["phase"], name: "index_imports_on_phase"
    t.index ["status"], name: "index_imports_on_status"
  end

  create_table "media", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_path"
    t.integer "import_id"
    t.string "media_type"
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.datetime "uploaded_at"
    t.datetime "variants_generated_at"
    t.string "variants_status", default: "pending"
    t.index ["file_path"], name: "index_media_on_file_path", unique: true
    t.index ["import_id"], name: "index_media_on_import_id"
    t.index ["source_url"], name: "index_media_on_source_url"
    t.index ["variants_status"], name: "index_media_on_variants_status"
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
    t.datetime "email_confirmation_sent_at"
    t.string "email_confirmation_token"
    t.integer "import_id"
    t.json "metadata", default: {}
    t.string "name"
    t.integer "newsletter_status", default: 0, null: false
    t.integer "paid_amount_cents"
    t.datetime "paid_at"
    t.string "paid_currency"
    t.string "password_digest"
    t.string "pending_email"
    t.integer "refunded_amount_cents"
    t.datetime "refunded_at"
    t.string "refunded_currency"
    t.integer "status", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_payment_intent_id"
    t.datetime "subscribed_at"
    t.integer "tier", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["access_token"], name: "index_members_on_access_token", unique: true
    t.index ["email"], name: "index_members_on_email", unique: true
    t.index ["import_id"], name: "index_members_on_import_id"
    t.index ["status"], name: "index_members_on_status"
    t.index ["stripe_customer_id"], name: "index_members_on_stripe_customer_id", unique: true
    t.index ["tier", "status"], name: "index_members_on_tier_and_status"
  end

  create_table "newsletter_sends", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "import_id"
    t.integer "member_id", null: false
    t.string "message_id"
    t.integer "post_id", null: false
    t.datetime "sent_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_id"], name: "index_newsletter_sends_on_import_id"
    t.index ["member_id"], name: "index_newsletter_sends_on_member_id"
    t.index ["message_id"], name: "index_newsletter_sends_on_message_id"
    t.index ["post_id", "member_id"], name: "index_newsletter_sends_on_post_id_and_member_id", unique: true
    t.index ["post_id"], name: "index_newsletter_sends_on_post_id"
  end

  create_table "pages", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path"
    t.json "metadata"
    t.datetime "updated_at", null: false
  end

  create_table "postmark_configs", force: :cascade do |t|
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.integer "mode", default: 0, null: false
    t.text "server_token"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.string "webhook_token"
  end

  create_table "posts", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path"
    t.integer "import_id"
    t.json "metadata", default: {}
    t.datetime "updated_at", null: false
    t.index ["import_id"], name: "index_posts_on_import_id"
  end

  create_table "products", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "file_path"
    t.json "metadata", default: {}
    t.datetime "updated_at", null: false
    t.index ["file_path"], name: "index_products_on_file_path", unique: true
  end

  create_table "recovery_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_recovery_codes_on_user_id"
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

  create_table "snipcart_configs", force: :cascade do |t|
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.integer "mode", default: 0, null: false
    t.text "secret_key_live"
    t.text "secret_key_test"
    t.text "snippet"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.integer "channel_hash", limit: 8, null: false
    t.datetime "created_at", null: false
    t.binary "payload", limit: 536870912, null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "static_site_sync_configs", force: :cascade do |t|
    t.integer "auth_mode", default: 0
    t.datetime "created_at", null: false
    t.string "host"
    t.datetime "last_pushed_at"
    t.string "last_verification_error"
    t.datetime "last_verified_at"
    t.text "password"
    t.integer "port", default: 22
    t.integer "protocol", default: 0, null: false
    t.string "remote_path"
    t.text "ssh_private_key"
    t.datetime "updated_at", null: false
    t.string "username"
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
    t.datetime "verified_at"
    t.string "webhook_signing_secret_live"
    t.string "webhook_signing_secret_test"
  end

  create_table "sync_configs", force: :cascade do |t|
    t.text "backup_passphrase"
    t.datetime "created_at", null: false
    t.text "peer_env"
    t.string "peer_url"
    t.string "ssh_key_path"
    t.text "token"
    t.datetime "updated_at", null: false
  end

  create_table "update_statuses", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "current_step"
    t.text "error_message"
    t.string "from_version"
    t.text "log"
    t.integer "progress_percent", default: 0
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "to_version"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_update_statuses_on_created_at"
    t.index ["status"], name: "index_update_statuses_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "donations", "members"
  add_foreign_key "media", "imports"
  add_foreign_key "media_references", "media"
  add_foreign_key "media_references", "posts"
  add_foreign_key "members", "imports"
  add_foreign_key "newsletter_sends", "imports"
  add_foreign_key "posts", "imports"
  add_foreign_key "recovery_codes", "users"
  add_foreign_key "sessions", "users"
end
