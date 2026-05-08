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

ActiveRecord::Schema[8.0].define(version: 2026_05_08_074718) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "gmail_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "email"
    t.string "access_token"
    t.string "encrypted_refresh_token"
    t.datetime "token_expires_at"
    t.datetime "last_sync_at"
    t.integer "sync_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_gmail_connections_on_user_id"
  end

  create_table "invoice_items", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.string "product_name"
    t.string "brand"
    t.string "model"
    t.string "category"
    t.text "description"
    t.jsonb "specifications"
    t.decimal "price", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_items_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "seller_name"
    t.decimal "total_amount"
    t.date "purchase_date"
    t.string "file_url"
    t.string "original_filename"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ocr_status"
    t.text "ocr_error_message"
    t.string "serial_number"
    t.string "platform_name"
    t.decimal "confidence_score", precision: 3, scale: 2
    t.json "metadata"
    t.integer "status", default: 0, null: false
    t.jsonb "raw_ai_data"
    t.string "invoice_number"
    t.string "product_image_url"
    t.integer "warranty_duration"
    t.date "expires_at"
    t.integer "warranty_status"
    t.index ["confidence_score"], name: "index_invoices_on_confidence_score"
    t.index ["ocr_status"], name: "index_invoices_on_ocr_status"
    t.index ["serial_number"], name: "index_invoices_on_serial_number"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["user_id", "created_at"], name: "index_invoices_on_user_id_and_created_at", order: { created_at: :desc }
    t.index ["user_id", "invoice_number"], name: "index_invoices_on_user_id_and_invoice_number_unique", unique: true, where: "(invoice_number IS NOT NULL)"
    t.index ["user_id", "status"], name: "index_invoices_on_user_id_and_status"
    t.index ["user_id"], name: "index_invoices_on_user_id"
  end

  create_table "item_warranties", force: :cascade do |t|
    t.bigint "invoice_item_id", null: false
    t.string "component_name"
    t.integer "duration_months"
    t.date "expires_at"
    t.date "start_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "warranty_type", default: "manufacturer", null: false
    t.jsonb "reminder_settings", default: {"enable_reminders"=>true, "reminder_days_before"=>[30, 7, 0]}, null: false
    t.datetime "notification_sent_at"
    t.integer "notification_status", default: 0
    t.index ["expires_at"], name: "index_warranties_on_expires_at"
    t.index ["invoice_item_id", "component_name", "warranty_type"], name: "idx_unique_warranty_per_item_component_type", unique: true
    t.index ["invoice_item_id", "expires_at"], name: "index_warranties_on_invoice_item_id_and_expires_at"
    t.index ["invoice_item_id"], name: "index_item_warranties_on_invoice_item_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "message", null: false
    t.integer "notification_type", null: false
    t.boolean "read", default: false, null: false
    t.string "action_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata"
    t.index ["created_at"], name: "idx_notifications_created_at"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at", order: { created_at: :desc }
    t.index ["user_id", "notification_type"], name: "idx_notifications_user_type"
    t.index ["user_id", "read"], name: "idx_notifications_user_read"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.string "brand"
    t.string "model_number"
    t.string "category"
    t.text "description"
    t.string "product_image_url"
    t.string "product_image_source"
    t.json "images"
    t.json "specifications"
    t.string "official_website"
    t.string "amazon_url"
    t.string "manufacturer_url"
    t.json "product_links"
    t.string "support_phone"
    t.string "support_email"
    t.string "support_website"
    t.text "support_info"
    t.json "contact_info"
    t.integer "standard_warranty_months"
    t.text "warranty_terms"
    t.string "warranty_info_url"
    t.string "data_source"
    t.datetime "last_synced_at"
    t.json "sync_metadata"
    t.string "search_keywords"
    t.integer "popularity_score", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand", "model_number"], name: "index_products_on_brand_and_model_number", unique: true
    t.index ["brand", "name"], name: "index_products_on_brand_and_name"
    t.index ["category"], name: "index_products_on_category"
    t.index ["model_number"], name: "index_products_on_model_number"
    t.index ["search_keywords"], name: "index_products_on_search_keywords"
  end

  create_table "reminders", force: :cascade do |t|
    t.datetime "remind_at", null: false
    t.integer "reminder_type", default: 0
    t.boolean "sent", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "sent_at"
    t.integer "user_id", null: false
    t.string "component"
    t.bigint "item_warranty_id", null: false
    t.index ["component"], name: "index_reminders_on_component"
    t.index ["item_warranty_id"], name: "index_reminders_on_item_warranty_id"
    t.index ["remind_at", "sent"], name: "idx_reminders_remind_sent"
    t.index ["user_id", "item_warranty_id", "reminder_type"], name: "idx_reminders_lookup"
    t.index ["user_id", "sent", "remind_at"], name: "index_reminders_on_user_id_and_sent_and_remind_at"
  end

  create_table "user_reminder_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "days_before_expiry", null: false
    t.integer "reminder_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "days_before_expiry", "reminder_type"], name: "index_user_reminder_preferences_on_user_and_days_and_type", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "first_name"
    t.string "last_name"
    t.string "google_uid"
    t.string "avatar_url"
    t.integer "role"
    t.datetime "last_sign_in_at"
    t.integer "sign_in_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "email_verified", default: false, null: false
    t.string "verification_token"
    t.datetime "verification_sent_at"
    t.datetime "email_verified_at"
    t.datetime "last_app_reminder_sent_at"
    t.datetime "welcome_email_sent_at"
    t.boolean "welcome_email_pending"
    t.boolean "warranty_alerts_enabled", default: true, null: false
    t.string "password_reset_token"
    t.datetime "password_reset_sent_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["email_verified"], name: "index_users_on_email_verified"
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
    t.index ["last_sign_in_at"], name: "index_users_on_last_sign_in_at"
    t.index ["password_reset_sent_at"], name: "index_users_on_password_reset_sent_at"
    t.index ["password_reset_token"], name: "index_users_on_password_reset_token", unique: true
    t.index ["verification_sent_at"], name: "index_users_on_verification_sent_at"
    t.index ["verification_token"], name: "index_users_on_verification_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "gmail_connections", "users"
  add_foreign_key "invoice_items", "invoices"
  add_foreign_key "invoices", "users"
  add_foreign_key "item_warranties", "invoice_items"
  add_foreign_key "notifications", "users"
  add_foreign_key "reminders", "item_warranties"
  add_foreign_key "reminders", "users"
  add_foreign_key "user_reminder_preferences", "users"
end
