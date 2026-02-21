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

ActiveRecord::Schema[8.1].define(version: 2026_02_21_103026) do
  create_table "activities", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.integer "from_status"
    t.integer "order_id", null: false
    t.integer "to_status"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_id"], name: "index_activities_on_order_id"
    t.index ["user_id"], name: "index_activities_on_user_id"
  end

  create_table "assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "order_id", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_id"], name: "index_assignments_on_order_id"
    t.index ["user_id"], name: "index_assignments_on_user_id"
  end

  create_table "certifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "employee_id", null: false
    t.date "expiry_date"
    t.date "issued_date"
    t.string "issuing_body"
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_certifications_on_employee_id"
    t.index ["expiry_date"], name: "index_certifications_on_expiry_date"
  end

  create_table "clients", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.string "code", null: false
    t.date "contract_start_date"
    t.string "country", default: "AE", null: false
    t.datetime "created_at", null: false
    t.string "credit_grade"
    t.string "currency", default: "USD"
    t.string "ecount_code"
    t.string "industry"
    t.string "name", null: false
    t.text "notes"
    t.string "payment_terms"
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["code"], name: "index_clients_on_code", unique: true
    t.index ["country"], name: "index_clients_on_country"
    t.index ["ecount_code"], name: "index_clients_on_ecount_code"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "order_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_id"], name: "index_comments_on_order_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.string "company_type", default: "branch", null: false
    t.integer "country_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "registration_number"
    t.datetime "updated_at", null: false
    t.index ["country_id", "name"], name: "index_companies_on_country_id_and_name"
    t.index ["country_id"], name: "index_companies_on_country_id"
  end

  create_table "contact_persons", force: :cascade do |t|
    t.integer "contactable_id", null: false
    t.string "contactable_type", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "language", default: "en"
    t.string "name", null: false
    t.string "nationality"
    t.text "notes"
    t.string "phone"
    t.boolean "primary", default: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "wechat"
    t.string "whatsapp"
    t.index ["contactable_type", "contactable_id"], name: "index_contact_persons_on_contactable"
    t.index ["contactable_type", "contactable_id"], name: "index_contact_persons_on_contactable_type_and_contactable_id"
    t.index ["email"], name: "index_contact_persons_on_email"
  end

  create_table "countries", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "flag_emoji"
    t.string "name", null: false
    t.string "name_en", null: false
    t.string "region"
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_countries_on_code", unique: true
  end

  create_table "departments", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code"
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "parent_id"
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_departments_on_company_id_and_name"
    t.index ["company_id"], name: "index_departments_on_company_id"
    t.index ["parent_id"], name: "index_departments_on_parent_id"
  end

  create_table "email_accounts", force: :cascade do |t|
    t.boolean "connected", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.text "gmail_access_token_ciphertext"
    t.text "gmail_refresh_token_ciphertext"
    t.datetime "last_synced_at"
    t.string "oauth_scope"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_email_accounts_on_user_id"
  end

  create_table "employee_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "employee_id", null: false
    t.date "end_date"
    t.text "notes"
    t.integer "project_id", null: false
    t.string "role"
    t.date "start_date", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "project_id"], name: "index_employee_assignments_on_employee_id_and_project_id"
    t.index ["employee_id"], name: "index_employee_assignments_on_employee_id"
    t.index ["project_id", "status"], name: "index_employee_assignments_on_project_id_and_status"
    t.index ["project_id"], name: "index_employee_assignments_on_project_id"
  end

  create_table "employees", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.string "department"
    t.integer "department_id"
    t.string "emergency_contact"
    t.string "emergency_phone"
    t.string "employment_type", default: "regular", null: false
    t.date "hire_date"
    t.string "job_title"
    t.string "name", null: false
    t.string "name_en"
    t.string "nationality", default: "KR", null: false
    t.text "notes"
    t.string "passport_number"
    t.string "phone"
    t.date "termination_date"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["active"], name: "index_employees_on_active"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["name"], name: "index_employees_on_name"
    t.index ["nationality"], name: "index_employees_on_nationality"
    t.index ["user_id"], name: "index_employees_on_user_id"
  end

  create_table "employment_contracts", force: :cascade do |t|
    t.decimal "base_salary", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.integer "employee_id", null: false
    t.date "end_date"
    t.text "notes"
    t.string "pay_frequency", default: "monthly", null: false
    t.integer "project_id"
    t.date "start_date", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id", "status"], name: "index_employment_contracts_on_employee_id_and_status"
    t.index ["employee_id"], name: "index_employment_contracts_on_employee_id"
    t.index ["end_date"], name: "index_employment_contracts_on_end_date"
    t.index ["project_id"], name: "index_employment_contracts_on_project_id"
  end

  create_table "import_logs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_details"
    t.integer "error_rows"
    t.string "filename"
    t.string "import_type", default: "products", null: false
    t.text "preview_data"
    t.string "result_file_path"
    t.string "source"
    t.integer "status"
    t.integer "success_rows"
    t.integer "total_rows"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["import_type"], name: "index_import_logs_on_import_type"
    t.index ["status"], name: "index_import_logs_on_status"
    t.index ["user_id"], name: "index_import_logs_on_user_id"
  end

  create_table "menu_permissions", force: :cascade do |t|
    t.boolean "can_create", default: false, null: false
    t.boolean "can_delete", default: false, null: false
    t.boolean "can_read", default: true, null: false
    t.boolean "can_update", default: false, null: false
    t.datetime "created_at", null: false
    t.string "menu_key", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["role", "menu_key"], name: "index_menu_permissions_on_role_and_menu_key", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.integer "client_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.string "customer_name"
    t.text "description"
    t.date "due_date"
    t.decimal "estimated_value", precision: 12, scale: 2
    t.string "item_name"
    t.text "original_email_body"
    t.string "original_email_from"
    t.string "original_email_subject"
    t.integer "priority", default: 1, null: false
    t.integer "project_id"
    t.integer "quantity"
    t.string "source_email_id"
    t.integer "status", default: 0, null: false
    t.integer "supplier_id"
    t.string "tags"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["client_id"], name: "index_orders_on_client_id"
    t.index ["due_date"], name: "index_orders_on_due_date"
    t.index ["project_id"], name: "index_orders_on_project_id"
    t.index ["source_email_id"], name: "index_orders_on_source_email_id", unique: true, where: "source_email_id IS NOT NULL"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["supplier_id"], name: "index_orders_on_supplier_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "brand"
    t.string "category"
    t.string "code"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.text "description"
    t.string "ecount_code"
    t.string "name"
    t.boolean "sika_product", default: false, null: false
    t.string "site_category"
    t.string "supplier_code"
    t.string "unit"
    t.decimal "unit_price", precision: 12, scale: 4
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_products_on_category"
    t.index ["code"], name: "index_products_on_code", unique: true
    t.index ["ecount_code"], name: "index_products_on_ecount_code"
    t.index ["sika_product"], name: "index_products_on_sika_product"
  end

  create_table "projects", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.decimal "budget", precision: 15, scale: 2
    t.integer "client_id", null: false
    t.string "code"
    t.string "country", default: "AE"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.text "description"
    t.date "end_date"
    t.string "location"
    t.string "name", null: false
    t.string "site_category"
    t.date "start_date"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_projects_on_client_id"
    t.index ["code"], name: "index_projects_on_code"
    t.index ["site_category"], name: "index_projects_on_site_category"
    t.index ["status"], name: "index_projects_on_status"
  end

  create_table "sheets_sync_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "employees_count", default: 0
    t.text "error_message"
    t.integer "orders_count", default: 0
    t.integer "projects_count", default: 0
    t.string "spreadsheet_id"
    t.string "status", default: "pending", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.integer "visas_count", default: 0
    t.index ["created_at"], name: "index_sheets_sync_logs_on_created_at"
    t.index ["status"], name: "index_sheets_sync_logs_on_status"
  end

  create_table "supplier_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.integer "lead_time_days"
    t.string "notes"
    t.decimal "price", precision: 10, scale: 2
    t.integer "product_id", null: false
    t.integer "supplier_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_supplier_products_on_product_id"
    t.index ["supplier_id", "product_id"], name: "index_supplier_products_on_supplier_id_and_product_id", unique: true
    t.index ["supplier_id"], name: "index_supplier_products_on_supplier_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.string "code"
    t.string "contact_email"
    t.string "contact_phone"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "credit_grade"
    t.string "currency", default: "USD"
    t.string "ecount_code"
    t.string "industry"
    t.integer "lead_time_days"
    t.string "name"
    t.text "notes"
    t.string "payment_terms"
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["code"], name: "index_suppliers_on_code", unique: true
    t.index ["ecount_code"], name: "index_suppliers_on_ecount_code"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "assignee_id"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date"
    t.integer "order_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_tasks_on_assignee_id"
    t.index ["order_id"], name: "index_tasks_on_order_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "branch"
    t.integer "company_id"
    t.string "company_name"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "locale"
    t.string "name"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "visas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "employee_id", null: false
    t.date "expiry_date", null: false
    t.date "issue_date"
    t.string "issuing_country", null: false
    t.text "notes"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "visa_number"
    t.string "visa_type", null: false
    t.index ["employee_id", "status"], name: "index_visas_on_employee_id_and_status"
    t.index ["employee_id"], name: "index_visas_on_employee_id"
    t.index ["expiry_date"], name: "index_visas_on_expiry_date"
  end

  add_foreign_key "activities", "orders"
  add_foreign_key "activities", "users"
  add_foreign_key "assignments", "orders"
  add_foreign_key "assignments", "users"
  add_foreign_key "certifications", "employees"
  add_foreign_key "comments", "orders"
  add_foreign_key "comments", "users"
  add_foreign_key "companies", "countries"
  add_foreign_key "departments", "companies"
  add_foreign_key "email_accounts", "users"
  add_foreign_key "employee_assignments", "employees"
  add_foreign_key "employee_assignments", "projects"
  add_foreign_key "employees", "departments"
  add_foreign_key "employees", "users"
  add_foreign_key "employment_contracts", "employees"
  add_foreign_key "employment_contracts", "projects"
  add_foreign_key "import_logs", "users"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "projects"
  add_foreign_key "orders", "suppliers"
  add_foreign_key "orders", "users"
  add_foreign_key "projects", "clients"
  add_foreign_key "supplier_products", "products"
  add_foreign_key "supplier_products", "suppliers"
  add_foreign_key "tasks", "orders"
  add_foreign_key "tasks", "users", column: "assignee_id"
  add_foreign_key "users", "companies"
  add_foreign_key "visas", "employees"
end
