# Ambiguous Column 정적 분석 — 2026년  5월  4일 월요일 13시 53분 24초 KST

## 패턴 1: where("col 컬럼명 비명시 (모호 컬럼 위험)

코드 모델/scope에서 `where("created_at"`, `where("updated_at"`, `where("status"` 등 테이블명 prefix 없는 컬럼 사용. JOIN 시 ambiguous column SQL 에러 가능.

```
app/controllers/search_controller.rb:25:    results += Client.where("name LIKE ? OR code LIKE ? OR ecount_code LIKE ?", like, like, like)
app/controllers/search_controller.rb:32:    results += Supplier.where("name LIKE ? OR code LIKE ? OR ecount_code LIKE ?", like, like, like)
app/controllers/search_controller.rb:39:    results += Employee.where("name LIKE ? OR name_en LIKE ? OR passport_number LIKE ?", like, like, like)
app/controllers/search_controller.rb:46:    results += Project.where("name LIKE ? OR code LIKE ? OR location LIKE ?", like, like, like)
app/controllers/clients_controller.rb:10:    @clients = @clients.where("name LIKE ? OR code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
app/controllers/clients_controller.rb:27:    @recent_30d_count     = Client.active.where("created_at >= ?", 30.days.ago).count
app/controllers/clients_controller.rb:124:    clients = clients.where("name LIKE ? OR code LIKE ?", "%#{q}%", "%#{q}%") if q.present?
app/controllers/employees_controller.rb:14:      @employees = @employees.where("name LIKE ? OR name_en LIKE ?",
app/controllers/suppliers_controller.rb:9:    @suppliers = @suppliers.where("name LIKE ? OR ecount_code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
app/controllers/suppliers_controller.rb:19:    @recent_30d_count   = Supplier.where("created_at >= ?", 30.days.ago).count
app/controllers/suppliers_controller.rb:118:    suppliers = suppliers.where("name LIKE ? OR ecount_code LIKE ?", "%#{q}%", "%#{q}%") if q.present?
app/controllers/team_controller.rb:55:                             .where("created_at >= ?", weeks.first[:start].beginning_of_day)
app/controllers/team_controller.rb:87:                        .where("created_at >= ?", thirty_days_ago)
app/controllers/admin/rfq_stats_controller.rb:21:                             .where("created_at >= ?", window.days.ago)
app/controllers/admin/rfq_stats_controller.rb:41:                             .where("created_at >= ?", window.days.ago)
app/controllers/admin/rfq_stats_controller.rb:82:      today_scope = ClassificationLog.v2.where("created_at >= ?", Time.current.beginning_of_day)
app/controllers/admin/rfq_stats_controller.rb:88:      last_24h = ClassificationLog.v2.where("created_at >= ?", 24.hours.ago)
app/controllers/admin/rfq_stats_controller.rb:102:                   .where("created_at >= ?", 7.days.ago)
app/controllers/admin/ecount/customers_controller.rb:29:          combined = combined.where("name LIKE ? OR ecount_code LIKE ? OR code LIKE ?", like, like, like)
app/controllers/admin/ecount/products_controller.rb:16:          scope = scope.where("name LIKE ? OR ecount_code LIKE ? OR description LIKE ?", like, like, like)
app/models/classification_log.rb:15:  scope :since_today,   -> { where("created_at >= ?", Time.current.beginning_of_day) }
app/models/ecount_sync_log.rb:10:  scope :failed_today, -> { where(status: :failed).where("created_at >= ?", Time.current.beginning_of_day) }
```

## 패턴 2: scope 안에서 컬럼 비명시

`scope :foo, -> { where("col ...") }` 형태 — 다른 scope과 chain 시 위험.

```
app/models/classification_log.rb:15:  scope :since_today,   -> { where("created_at >= ?", Time.current.beginning_of_day) }
app/models/ecount_sync_log.rb:10:  scope :failed_today, -> { where(status: :failed).where("created_at >= ?", Time.current.beginning_of_day) }
```

## 패턴 3: joins + 같은 컬럼명 가진 모델 (잠재 위험)

`joins(:user)` 같은 형태에서 양쪽 테이블이 모두 created_at/updated_at/status 등 보유한 경우.

```
app/controllers/application_controller.rb:64:    base.joins(:user).where(users: { branch: current_user.branch })
app/controllers/clients_controller.rb:162:    quote_counts = all_orders.joins("LEFT JOIN order_quotes ON order_quotes.order_id = orders.id")
app/controllers/orders_controller.rb:22:    @orders = @orders.joins(:assignments).where(assignments: { employee_id: params[:employee_id] }) if params[:employee_id].present?
app/controllers/orders_controller.rb:26:      @orders = @orders.left_joins(:assignments).where(assignments: { id: nil }).distinct
app/controllers/dashboard_controller.rb:16:                              .left_joins(:assignments)
app/controllers/dashboard_controller.rb:54:    @top_clients = Client.joins(:orders)
app/controllers/dashboard_controller.rb:59:    @top_suppliers = Supplier.joins(:orders)
app/controllers/dashboard_controller.rb:67:      .joins(assignments: :order)
app/controllers/employees_controller.rb:24:      @employees = @employees.joins(:visas).merge(Visa.expiring_within(60)).distinct
app/controllers/employees_controller.rb:26:      @employees = @employees.joins(:employment_contracts).merge(EmploymentContract.expiring_within(30)).distinct
app/controllers/employees_controller.rb:33:      visa_expiring:     Employee.active.joins(:visas).merge(Visa.expiring_within(60)).distinct.count,
app/controllers/employees_controller.rb:35:      visa_renewal_needed: Employee.active.joins(:visas)
app/controllers/employees_controller.rb:38:      visa_in_renewal:   Employee.active.joins(:visas)
app/controllers/employees_controller.rb:41:      contract_expiring: Employee.active.joins(:employment_contracts)
app/controllers/trash_controller.rb:7:    @orders = current_user.admin? ? base : base.joins(:user).where(users: { branch: current_user.branch })
app/controllers/trash_controller.rb:37:    base = base.joins(:user).where(users: { branch: current_user.branch }) unless current_user.admin?
app/controllers/reports_controller.rb:79:      base = base.where(user_id: branch_user_ids).or(base.joins(:assignees).where(users: { id: branch_user_ids }))
app/controllers/reports_controller.rb:83:      base = base.joins(:assignees).where(users: { id: @selected_assignee_id })
app/controllers/reports_controller.rb:126:      urgent:         report_scoped_orders.joins(:card_status).where(card_statuses: { key: %w[urgent high overdue] }).where.not(status: [ :get_grn, :give_up, :done ]).count,
app/controllers/reports_controller.rb:185:    report_scoped_orders.joins(:client).where(created_at: range)
app/controllers/reports_controller.rb:191:    report_scoped_orders.joins(:supplier).where(created_at: range)
app/controllers/reports_controller.rb:197:    report_scoped_orders.joins(:project).where(created_at: range)
app/controllers/reports_controller.rb:204:    scope = User.joins(:created_orders)
app/controllers/reports_controller.rb:224:                .joins(:created_orders)
app/controllers/projects_controller.rb:28:    @active_order_count = Order.joins(:project).where(projects: { status: :active }).count
app/controllers/admin/rfq_stats_controller.rb:104:                   .joins(:order)
app/models/employee.rb:69:  scope :dispatched, -> { joins(:employee_assignments).where(employee_assignments: { status: "active" }).distinct }
app/models/country.rb:15:    Employee.joins(department: :company).where(companies: { country_id: id }).count
app/models/contact_person.rb:29:    joins(
app/models/order.rb:173:    joins(:card_status)
```

## 권장 조치

패턴 1, 2의 모든 항목을 `테이블명.컬럼명` 형태로 명시 변경. 예:
- ✗ `where("updated_at >= ?", time)`
- ✓ `where("orders.updated_at >= ?", time)`
