# Feature Design: phase4-hr

**Feature Name**: Phase 4 HR 완성 (직원·조직도·팀 Gap 보완)
**Based On**: `docs/01-plan/features/phase4-hr.plan.md`
**Created**: 2026-02-28
**Phase**: Design

---

## AS-IS 코드 실측 결과

### dashboard_controller.rb
- **line 42–47**: `@expiring_visas` — Visa 90일 이내, limit 5 ✅
- **@expiring_contracts**: 없음 ❌ → FR-01 구현 필요

### team_controller.rb
```ruby
def show
  @member = User.find(params[:id])
  @active_orders = @member.assigned_orders.active.by_due_date.limit(10)
  # @status_counts 없음 ❌
end
```

### employees_controller.rb
- **line 13**: `@employees.where(department: params[:department])` ❌
  - `department`는 레거시 문자열 컬럼 → `department_id` 기준으로 수정 필요

### employee.rb
- `current_contract`, `current_assignment`, `active_visa` 있음 ✅
- **`current_project`**: 없음 ❌ → FR-04 구현 필요

### org_chart/index.html.erb
- **line 135**: `dept.employees.select(&:active?).sort_by(&:name)` — department_id 있는 직원만 표시
- **부서 미배정 직원 섹션**: 없음 ❌ → FR-05 구현 필요

### dashboard/index.html.erb
- **line 334–362**: 비자 만료 섹션 (`<!-- 비자 만료 현황 -->`) 완전 구현됨 ✅
- **계약 만료 섹션**: 없음 ❌ → FR-01에서 비자 섹션 바로 아래(line 362 이후)에 삽입

---

## Gap별 구현 설계

### FR-01: 대시보드 계약 만료 임박 섹션

**파일 1: `app/controllers/dashboard_controller.rb`**

line 47 (`@expiring_visas` 쿼리) 바로 아래에 추가:

```ruby
# 계약 만료 임박 (30일 이내)
@expiring_contracts = EmploymentContract.expiring_within(30)
                                        .order(:end_date)
                                        .includes(:employee)
                                        .limit(5)
```

- `EmploymentContract.expiring_within(30)` scope: `active.where("end_date IS NOT NULL AND end_date <= ?", 30.days.from_now.to_date)` — 이미 존재 ✅

**파일 2: `app/views/dashboard/index.html.erb`**

line 362 (`</div>` 비자 섹션 닫힘) 바로 아래에 삽입:

```erb
<!-- 계약 만료 현황 -->
<div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700">
  <div class="flex items-center justify-between px-5 py-3 border-b border-gray-100 dark:border-gray-700">
    <h3 class="text-sm font-semibold text-gray-900 dark:text-white">계약 만료 임박</h3>
    <% total_expiring_contracts = EmploymentContract.expiring_within(30).count %>
    <% if total_expiring_contracts > 0 %>
      <span class="text-xs bg-orange-100 dark:bg-orange-900/40 text-orange-600 dark:text-orange-400 px-2 py-0.5 rounded-full font-medium"><%= total_expiring_contracts %>건</span>
    <% end %>
  </div>
  <div class="divide-y divide-gray-50 dark:divide-gray-700/50">
    <% if @expiring_contracts.empty? %>
      <div class="px-5 py-6 text-center text-xs text-gray-400 dark:text-gray-500">만료 임박 계약 없음</div>
    <% else %>
      <% @expiring_contracts.each do |contract| %>
        <% days = (contract.end_date - Date.today).to_i %>
        <% lvl_cls = days <= 7 ? 'text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20' : days <= 14 ? 'text-orange-600 dark:text-orange-400 bg-orange-50 dark:bg-orange-900/20' : 'text-yellow-600 dark:text-yellow-400 bg-yellow-50 dark:bg-yellow-900/20' %>
        <div class="flex items-center gap-3 px-4 py-3">
          <div class="w-10 h-10 rounded-lg flex items-center justify-center shrink-0 <%= lvl_cls.split.last(2).join(' ') %>">
            <span class="text-xs font-bold <%= lvl_cls.split.first %>">D-<%= days %></span>
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-xs font-medium text-gray-900 dark:text-white truncate"><%= contract.employee&.name %></p>
            <p class="text-xs text-gray-400 dark:text-gray-500"><%= contract.contract_type_label rescue contract.contract_type %> · <%= contract.end_date&.strftime("%Y.%m.%d") %></p>
          </div>
          <%= link_to employee_path(contract.employee), class: "text-xs text-primary hover:underline shrink-0" do %>보기<% end %>
        </div>
      <% end %>
    <% end %>
  </div>
</div>
```

---

### FR-02: Team show 페이지 상태별 오더 통계 뱃지

**파일 1: `app/controllers/team_controller.rb`**

show 액션의 `@active_orders` 아래에 추가:

```ruby
# 상태별 오더 건수 (뱃지용)
@status_counts = @member.assigned_orders.group(:status).count
```

**파일 2: `app/views/team/show.html.erb`**

헤더 카드(`</div>` line 25) 바로 아래에 상태 요약 뱃지 섹션 삽입:

```erb
<%# 상태별 통계 뱃지 %>
<% if @status_counts.any? %>
  <div class="flex flex-wrap gap-2">
    <% Order.statuses.keys.each do |status_key| %>
      <% count = @status_counts[status_key] || 0 %>
      <% next if count == 0 %>
      <span class="inline-flex items-center gap-1 text-xs px-2.5 py-1 rounded-full bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 font-medium">
        <%= Order::STATUS_LABELS[status_key] %>
        <span class="bg-white dark:bg-gray-600 text-gray-800 dark:text-gray-200 px-1.5 py-0.5 rounded-full text-xs font-bold"><%= count %></span>
      </span>
    <% end %>
  </div>
<% end %>
```

---

### FR-03: 직원 index 부서 필터 → department_id 기준

**파일: `app/controllers/employees_controller.rb`**

line 13 수정 (한 줄 변경):

```ruby
# 변경 전
@employees = @employees.where(department: params[:department]) if params[:department].present?

# 변경 후
@employees = @employees.where(department_id: params[:department]) if params[:department].present?
```

- `params[:department]`로 받되 `department_id` FK 필드로 필터링
- 뷰의 필터 form에서 `<select name="department">` 값으로 department_id를 넘기고 있는지 확인 필요

---

### FR-04: Employee#current_project 메서드 추가

**파일: `app/models/employee.rb`**

line 26 (`active_visa` 메서드) 아래에 추가:

```ruby
def current_project   = current_assignment&.project
```

- `current_assignment`는 이미 있는 메서드 (`employee_assignments.where(status: "active").order(start_date: :desc).first`)
- `EmployeeAssignment` belongs_to `:project` 이므로 `.project` 호출 가능

---

### FR-05: 조직도 — 부서 미배정 직원 섹션

**파일: `app/views/org_chart/index.html.erb`**

각 국가별 법인 트리 렌더링 블록(`<% companies.each do |company| %>`) 종료 후,
`</div>` (line 200) 바로 **전**에 미배정 직원 섹션 삽입:

```erb
<%# 부서 미배정 직원 %>
<% unassigned = country.companies.flat_map { |c| c.employees.active.select { |e| e.department_id.nil? } }.sort_by(&:name) %>
<% if unassigned.any? %>
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-dashed border-gray-300 dark:border-gray-600 overflow-hidden mt-4">
    <div class="flex items-center gap-2 px-5 py-3 border-b border-gray-100 dark:border-gray-700">
      <svg class="w-4 h-4 text-gray-400 dark:text-gray-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <h3 class="text-sm font-medium text-gray-500 dark:text-gray-400">부서 미배정 (<%= unassigned.count %>명)</h3>
    </div>
    <div class="px-5 py-4">
      <div class="flex flex-wrap gap-2">
        <% unassigned.each do |emp| %>
          <%= link_to employee_path(emp), class: "flex items-center gap-2 px-3 py-1.5 bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 rounded-lg hover:border-primary/50 hover:shadow-sm transition-all" do %>
            <div class="w-6 h-6 rounded-full bg-gray-200 dark:bg-gray-600 flex items-center justify-center text-gray-600 dark:text-gray-300 text-xs font-bold flex-shrink-0">
              <%= emp.name.first.upcase %>
            </div>
            <div>
              <p class="text-xs font-medium text-gray-900 dark:text-white"><%= emp.name %></p>
              <% if emp.job_title.present? %>
                <p class="text-xs text-gray-400 dark:text-gray-500"><%= emp.job_title %></p>
              <% end %>
            </div>
            <% if emp.active_visa %>
              <span class="w-2 h-2 rounded-full flex-shrink-0 <%= emp.visa_expiring_soon? ? 'bg-red-400' : 'bg-green-400' %>"></span>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

**주의**: `country.companies.flat_map { |c| c.employees.active.select { |e| e.department_id.nil? } }` 는 N+1 쿼리 위험.
→ `org_chart_controller`에서 `@unassigned_by_country` 사전 로드 고려 (선택사항 — 직원 수가 적으므로 뷰 내 계산도 허용)

---

## 구현 순서

| 순서 | 파일 | 변경 내용 | 난이도 |
|------|------|-----------|--------|
| 1 | `app/models/employee.rb` | `current_project` 메서드 1줄 추가 | ⭐ |
| 2 | `app/controllers/employees_controller.rb` | line 13 `department` → `department_id` 수정 | ⭐ |
| 3 | `app/controllers/dashboard_controller.rb` | `@expiring_contracts` 쿼리 추가 | ⭐ |
| 4 | `app/views/dashboard/index.html.erb` | 계약 만료 섹션 HTML 삽입 | ⭐⭐ |
| 5 | `app/controllers/team_controller.rb` | `@status_counts` 쿼리 추가 | ⭐ |
| 6 | `app/views/team/show.html.erb` | 상태별 통계 뱃지 HTML 삽입 | ⭐⭐ |
| 7 | `app/views/org_chart/index.html.erb` | 미배정 직원 섹션 HTML 삽입 | ⭐⭐ |

**총 수정 파일: 7개 / 예상 추가 코드: ~80줄**

---

## 의존성 & 사전 확인 사항

| 항목 | 상태 | 비고 |
|------|:----:|------|
| `EmploymentContract.expiring_within(days)` scope | ✅ | 이미 구현됨 |
| `EmploymentContract belongs_to :employee` | ✅ | 확인됨 |
| `EmployeeAssignment belongs_to :project` | ✅ | employee.rb 연관관계 확인됨 |
| `Order::STATUS_LABELS` Hash | ✅ | order.rb line 56 |
| `User#assigned_orders` 연관관계 | ✅ | team_controller 이미 사용 중 |
| `Employee#department_id` FK | ✅ | employee_params에 포함 |

---

## 범위 외 (이번 사이클 제외)

- HR 이메일/Notification Job
- 직원 사진 업로드
- 급여 관리
- 조직도 N+1 최적화 (해결 안 해도 기능상 무방)
