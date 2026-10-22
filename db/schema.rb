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

ActiveRecord::Schema[8.0].define(version: 2026_10_22_100000) do
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

  create_table "check_items", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "check_id", null: false
    t.bigint "kitchen_order_id"
    t.bigint "product_id"
    t.string "name", null: false
    t.decimal "unit_price", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "quantity", default: 1, null: false
    t.text "note"
    t.bigint "station_id"
    t.integer "status", default: 0, null: false
    t.datetime "preparing_at"
    t.datetime "ready_at"
    t.datetime "delivered_at"
    t.datetime "cancelled_at"
    t.text "cancel_reason"
    t.bigint "cancelled_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cancelled_by_id"], name: "index_check_items_on_cancelled_by_id"
    t.index ["check_id"], name: "index_check_items_on_check_id"
    t.index ["company_id"], name: "index_check_items_on_company_id"
    t.index ["kitchen_order_id"], name: "index_check_items_on_kitchen_order_id"
    t.index ["product_id"], name: "index_check_items_on_product_id"
    t.index ["station_id", "status"], name: "index_check_items_on_station_id_and_status"
    t.index ["station_id"], name: "index_check_items_on_station_id"
  end

  create_table "check_payments", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "check_id", null: false
    t.integer "payment_method", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "reference"
    t.decimal "amount_received", precision: 10, scale: 2
    t.decimal "change_given", precision: 10, scale: 2
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "terminal_id"
    t.integer "source", default: 0, null: false
    t.index ["check_id"], name: "index_check_payments_on_check_id"
    t.index ["company_id"], name: "index_check_payments_on_company_id"
    t.index ["created_by_id"], name: "index_check_payments_on_created_by_id"
    t.index ["terminal_id"], name: "index_check_payments_on_terminal_id"
  end

  create_table "checks", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "dining_table_id"
    t.string "takeout_name"
    t.bigint "opened_by_id", null: false
    t.bigint "waiter_id", null: false
    t.integer "status", default: 0, null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "opened_at", null: false
    t.datetime "closed_at"
    t.text "cancel_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "status"], name: "index_checks_on_company_id_and_status"
    t.index ["company_id"], name: "index_checks_on_company_id"
    t.index ["dining_table_id"], name: "index_checks_on_dining_table_id"
    t.index ["dining_table_id"], name: "index_checks_on_open_dining_table", unique: true, where: "(status = 0)"
    t.index ["opened_by_id"], name: "index_checks_on_opened_by_id"
    t.index ["waiter_id"], name: "index_checks_on_waiter_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "stripe_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "disabled_modules", default: [], null: false, array: true
    t.bigint "parent_company_id"
    t.integer "order_mode", default: 0, null: false
    t.index ["parent_company_id"], name: "index_companies_on_parent_company_id"
  end

  create_table "dining_tables", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_dining_tables_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_dining_tables_on_company_id"
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

  create_table "idempotency_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "key", limit: 64, null: false
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.integer "response_status", null: false
    t.text "response_body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_idempotency_keys_on_created_at"
    t.index ["user_id", "key"], name: "index_idempotency_keys_on_user_id_and_key", unique: true
  end

  create_table "kitchen_orders", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "check_id", null: false
    t.bigint "sent_by_id", null: false
    t.datetime "sent_at", null: false
    t.integer "number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["check_id", "number"], name: "index_kitchen_orders_on_check_id_and_number", unique: true
    t.index ["check_id"], name: "index_kitchen_orders_on_check_id"
    t.index ["company_id"], name: "index_kitchen_orders_on_company_id"
    t.index ["sent_by_id"], name: "index_kitchen_orders_on_sent_by_id"
  end

  create_table "module_changes", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "actor_id", null: false
    t.string "module", null: false
    t.boolean "enabled", null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_module_changes_on_actor_id"
    t.index ["company_id", "created_at"], name: "index_module_changes_on_company_id_and_created_at"
    t.index ["company_id"], name: "index_module_changes_on_company_id"
  end

  create_table "payment_terminals", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "company_id, lower((name)::text)", name: "index_payment_terminals_on_company_and_lower_name", unique: true
    t.index ["company_id"], name: "index_payment_terminals_on_company_id"
  end

  create_table "product_types", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "kind"
    t.boolean "sellable", default: true, null: false
    t.boolean "counted", default: false, null: false
    t.boolean "fractional", default: false, null: false
    t.string "default_unit_key", default: "pza", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "icon"
    t.index "company_id, lower((name)::text)", name: "index_product_types_on_company_and_lower_name", unique: true
    t.index ["company_id"], name: "index_product_types_on_company_id"
  end

  create_table "products", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "sku"
    t.string "name"
    t.decimal "stock", precision: 12, scale: 3, default: "0.0"
    t.decimal "min_stock", precision: 12, scale: 3
    t.decimal "unit_cost"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "price", precision: 10, scale: 2
    t.string "category"
    t.text "description"
    t.boolean "available", default: true, null: false
    t.boolean "tracks_stock", default: false, null: false
    t.bigint "station_id"
    t.bigint "product_type_id", null: false
    t.string "unit_key"
    t.string "icon"
    t.index ["available"], name: "index_products_on_available"
    t.index ["category"], name: "index_products_on_category"
    t.index ["company_id"], name: "index_products_on_company_id"
    t.index ["product_type_id"], name: "index_products_on_product_type_id"
    t.index ["station_id"], name: "index_products_on_station_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.boolean "is_default", default: false, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_stations_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_stations_on_company_id"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "company_id", null: false
    t.integer "movement_type"
    t.decimal "qty", precision: 12, scale: 3
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

  create_table "subscription_changes", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "subscription_id", null: false
    t.bigint "actor_id"
    t.string "kind", null: false
    t.string "from_plan"
    t.string "to_plan"
    t.string "reason"
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_subscription_changes_on_actor_id"
    t.index ["company_id"], name: "index_subscription_changes_on_company_id"
    t.index ["subscription_id"], name: "index_subscription_changes_on_subscription_id"
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
    t.datetime "past_due_since"
    t.datetime "suspended_at"
    t.string "suspension_reason"
    t.string "pending_invoice_url"
    t.datetime "past_due_notice_sent_at"
    t.datetime "cancel_warning_sent_at"
    t.index ["company_id"], name: "index_subscriptions_on_company_id", unique: true
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true, where: "(stripe_subscription_id IS NOT NULL)"
    t.index ["trial_ends_at"], name: "index_subscriptions_on_trial_ends_at"
  end

  create_table "ticket_payments", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "ticket_id", null: false
    t.integer "payment_method", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "amount_received", precision: 10, scale: 2
    t.decimal "change_given", precision: 10, scale: 2
    t.bigint "terminal_id"
    t.string "authorization_code"
    t.string "card_last4", limit: 4
    t.string "reference"
    t.integer "source", default: 0, null: false
    t.bigint "created_by_id", null: false
    t.datetime "voided_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_ticket_payments_on_company_id"
    t.index ["created_by_id"], name: "index_ticket_payments_on_created_by_id"
    t.index ["terminal_id"], name: "index_ticket_payments_on_terminal_id"
    t.index ["ticket_id"], name: "index_ticket_payments_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.bigint "work_order_id"
    t.bigint "company_id", null: false
    t.string "folio", null: false
    t.integer "status", default: 0, null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "paid_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "payment_method"
    t.decimal "amount_received", precision: 10, scale: 2
    t.decimal "change_given", precision: 10, scale: 2
    t.string "charged_by_type"
    t.bigint "charged_by_id"
    t.datetime "voided_at"
    t.string "voided_by_type"
    t.bigint "voided_by_id"
    t.text "void_reason"
    t.bigint "check_id"
    t.index ["charged_by_type", "charged_by_id"], name: "index_tickets_on_charged_by"
    t.index ["check_id"], name: "index_tickets_on_check_id", unique: true
    t.index ["company_id"], name: "index_tickets_on_company_id"
    t.index ["folio"], name: "index_tickets_on_folio", unique: true
    t.index ["status"], name: "index_tickets_on_status"
    t.index ["voided_by_type", "voided_by_id"], name: "index_tickets_on_voided_by"
    t.index ["work_order_id"], name: "index_tickets_on_work_order_id", unique: true
    t.check_constraint "(work_order_id IS NULL) <> (check_id IS NULL)", name: "tickets_one_owner"
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
    t.string "theme", default: "anaquel", null: false
    t.string "color_mode", default: "system", null: false
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

  create_table "work_order_events", force: :cascade do |t|
    t.bigint "work_order_id", null: false
    t.integer "kind", null: false
    t.string "actor_type", null: false
    t.bigint "actor_id", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_work_order_events_on_actor"
    t.index ["work_order_id", "created_at"], name: "index_work_order_events_on_work_order_id_and_created_at"
  end

  create_table "work_order_items", force: :cascade do |t|
    t.bigint "work_order_id", null: false
    t.string "description"
    t.decimal "quantity"
    t.string "unit"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "product_id"
    t.decimal "unit_price", precision: 10, scale: 2
    t.index ["product_id"], name: "index_work_order_items_on_product_id"
    t.index ["work_order_id"], name: "index_work_order_items_on_work_order_id"
  end

  create_table "work_order_steps", force: :cascade do |t|
    t.bigint "work_order_id", null: false
    t.string "description", null: false
    t.integer "position", default: 0, null: false
    t.datetime "done_at"
    t.string "done_by_type"
    t.bigint "done_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["done_by_type", "done_by_id"], name: "index_work_order_steps_on_done_by"
    t.index ["work_order_id"], name: "index_work_order_steps_on_work_order_id"
  end

  create_table "work_orders", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "employee_id"
    t.string "created_by_type", null: false
    t.bigint "created_by_id", null: false
    t.string "title"
    t.text "description"
    t.integer "priority"
    t.integer "status", default: 0, null: false
    t.datetime "due_date"
    t.datetime "completed_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.string "customer_name"
    t.string "customer_phone"
    t.text "customer_address"
    t.datetime "started_at"
    t.text "cancel_reason"
    t.index ["company_id"], name: "index_work_orders_on_company_id"
    t.index ["created_by_type", "created_by_id"], name: "index_work_orders_on_created_by"
    t.index ["created_by_type", "created_by_id"], name: "index_work_orders_on_created_by_type_and_created_by_id"
    t.index ["employee_id"], name: "index_work_orders_on_employee_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "attendances", "companies"
  add_foreign_key "attendances", "employees"
  add_foreign_key "check_items", "checks"
  add_foreign_key "check_items", "companies"
  add_foreign_key "check_items", "kitchen_orders"
  add_foreign_key "check_items", "products"
  add_foreign_key "check_items", "stations"
  add_foreign_key "check_items", "users", column: "cancelled_by_id"
  add_foreign_key "check_payments", "checks"
  add_foreign_key "check_payments", "companies"
  add_foreign_key "check_payments", "payment_terminals", column: "terminal_id"
  add_foreign_key "check_payments", "users", column: "created_by_id"
  add_foreign_key "checks", "companies"
  add_foreign_key "checks", "dining_tables"
  add_foreign_key "checks", "users", column: "opened_by_id"
  add_foreign_key "checks", "users", column: "waiter_id"
  add_foreign_key "dining_tables", "companies"
  add_foreign_key "employees", "companies"
  add_foreign_key "employees", "users"
  add_foreign_key "idempotency_keys", "users"
  add_foreign_key "kitchen_orders", "checks"
  add_foreign_key "kitchen_orders", "companies"
  add_foreign_key "kitchen_orders", "users", column: "sent_by_id"
  add_foreign_key "module_changes", "companies"
  add_foreign_key "module_changes", "users", column: "actor_id"
  add_foreign_key "payment_terminals", "companies"
  add_foreign_key "product_types", "companies"
  add_foreign_key "products", "companies"
  add_foreign_key "products", "product_types"
  add_foreign_key "products", "stations"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "stations", "companies"
  add_foreign_key "stock_movements", "companies"
  add_foreign_key "stock_movements", "products"
  add_foreign_key "subscription_changes", "companies"
  add_foreign_key "subscription_changes", "subscriptions"
  add_foreign_key "subscription_changes", "users", column: "actor_id"
  add_foreign_key "subscriptions", "companies"
  add_foreign_key "ticket_payments", "companies"
  add_foreign_key "ticket_payments", "payment_terminals", column: "terminal_id"
  add_foreign_key "ticket_payments", "tickets"
  add_foreign_key "ticket_payments", "users", column: "created_by_id"
  add_foreign_key "tickets", "checks"
  add_foreign_key "tickets", "companies"
  add_foreign_key "tickets", "work_orders"
  add_foreign_key "user_companies", "companies"
  add_foreign_key "user_companies", "users"
  add_foreign_key "work_order_attachments", "work_orders"
  add_foreign_key "work_order_events", "work_orders"
  add_foreign_key "work_order_items", "products"
  add_foreign_key "work_order_items", "work_orders"
  add_foreign_key "work_order_steps", "work_orders"
  add_foreign_key "work_orders", "companies"
  add_foreign_key "work_orders", "employees"
end
