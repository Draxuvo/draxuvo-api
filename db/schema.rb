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

ActiveRecord::Schema[8.0].define(version: 2026_10_15_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_on_all"
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

  create_table "attendances", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.bigint "company_id", null: false
    t.datetime "checkin_at"
    t.datetime "checkout_at"
    t.decimal "lat"
    t.decimal "lng"
    t.integer "attendance_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_attendances_on_company_id"
    t.index ["employee_id"], name: "index_attendances_on_employee_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "stripe_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "disabled_modules", default: [], null: false, array: true
    t.bigint "parent_company_id"
    t.index ["parent_company_id"], name: "index_companies_on_parent_company_id"
  end

  create_table "employees", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name"
    t.string "position"
    t.string "department"
    t.decimal "salary"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "email"
    t.string "phone"
    t.index ["company_id"], name: "index_employees_on_company_id"
    t.index ["email"], name: "index_employees_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["user_id"], name: "index_employees_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "sku"
    t.string "name"
    t.integer "stock"
    t.integer "min_stock"
    t.decimal "unit_cost"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "price", precision: 10, scale: 2
    t.string "category"
    t.text "description"
    t.boolean "available", default: true, null: false
    t.index ["available"], name: "index_products_on_available"
    t.index ["category"], name: "index_products_on_category"
    t.index ["company_id"], name: "index_products_on_company_id"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "company_id", null: false
    t.integer "movement_type"
    t.integer "qty"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_stock_movements_on_company_id"
    t.index ["product_id"], name: "index_stock_movements_on_product_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.string "stripe_event_id", null: false
    t.string "event_type", null: false
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_events_on_stripe_event_id", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.integer "plan", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.integer "billing_cycle", default: 0, null: false
    t.integer "amount_cents", default: 0, null: false
    t.datetime "trial_ends_at"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.string "stripe_subscription_id"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "cancel_at_period_end", default: false, null: false
    t.string "stripe_price_lookup_key"
    t.index ["company_id"], name: "index_subscriptions_on_company_id", unique: true
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_ends_at"], name: "index_subscriptions_on_trial_ends_at"
  end

  create_table "tickets", force: :cascade do |t|
    t.bigint "work_order_id", null: false
    t.bigint "company_id", null: false
    t.string "folio", null: false
    t.integer "status", default: 0, null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "paid_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_tickets_on_company_id"
    t.index ["folio"], name: "index_tickets_on_folio", unique: true
    t.index ["status"], name: "index_tickets_on_status"
    t.index ["work_order_id"], name: "index_tickets_on_work_order_id", unique: true
  end

  create_table "units", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.string "group", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group"], name: "index_units_on_group"
    t.index ["key"], name: "index_units_on_key", unique: true
  end

  create_table "user_companies", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.index ["company_id"], name: "index_user_companies_on_company_id"
    t.index ["user_id", "company_id"], name: "index_user_companies_on_user_id_and_company_id", unique: true
    t.index ["user_id"], name: "index_user_companies_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name"
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "middle_name"
    t.string "last_name"
    t.string "second_last_name"
    t.string "phone"
    t.boolean "active", default: false
    t.integer "role"
    t.text "description"
  end

  create_table "work_order_attachments", force: :cascade do |t|
    t.bigint "work_order_id", null: false
    t.string "uploaded_by_type", null: false
    t.bigint "uploaded_by_id", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["uploaded_by_type", "uploaded_by_id"], name: "index_work_order_attachments_on_uploaded_by"
    t.index ["work_order_id"], name: "index_work_order_attachments_on_work_order_id"
  end

  create_table "work_order_items", force: :cascade do |t|
    t.bigint "work_order_id", null: false
    t.string "description"
    t.decimal "quantity"
    t.string "unit"
    t.integer "status"
    t.integer "position"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "product_id"
    t.decimal "unit_price", precision: 10, scale: 2
    t.index ["product_id"], name: "index_work_order_items_on_product_id"
    t.index ["work_order_id"], name: "index_work_order_items_on_work_order_id"
  end

  create_table "work_orders", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "employee_id"
    t.string "created_by_type", null: false
    t.bigint "created_by_id", null: false
    t.string "title"
    t.text "description"
    t.integer "priority"
    t.integer "status"
    t.datetime "due_date"
    t.datetime "completed_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["company_id"], name: "index_work_orders_on_company_id"
    t.index ["created_by_type", "created_by_id"], name: "index_work_orders_on_created_by"
    t.index ["created_by_type", "created_by_id"], name: "index_work_orders_on_created_by_type_and_created_by_id"
    t.index ["employee_id"], name: "index_work_orders_on_employee_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "attendances", "companies"
  add_foreign_key "attendances", "employees"
  add_foreign_key "employees", "companies"
  add_foreign_key "employees", "users"
  add_foreign_key "products", "companies"
  add_foreign_key "stock_movements", "companies"
  add_foreign_key "stock_movements", "products"
  add_foreign_key "subscriptions", "companies"
  add_foreign_key "tickets", "companies"
  add_foreign_key "tickets", "work_orders"
  add_foreign_key "user_companies", "companies"
  add_foreign_key "user_companies", "users"
  add_foreign_key "work_order_attachments", "work_orders"
  add_foreign_key "work_order_items", "products"
  add_foreign_key "work_order_items", "work_orders"
  add_foreign_key "work_orders", "companies"
  add_foreign_key "work_orders", "employees"
end
