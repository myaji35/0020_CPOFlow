# Design: dashboard-kpi

## 개요

대시보드 KPI 강화 — 담당자별 워크로드 위젯 신규 추가

- **Plan**: `docs/01-plan/features/dashboard-kpi.plan.md`
- **작성일**: 2026-02-28

---

## 실측 기반 현황

### 변경 불필요 (이미 완성)
- Top5 발주처 위젯 (`@top_clients`) — ROW 5, L460~495 ✅
- Top5 거래처 위젯 (`@top_suppliers`) — ROW 5, L497~531 ✅

### 변경 대상 (신규 추가)
| 파일 | 변경 | 내용 |
|------|------|------|
| `app/controllers/dashboard_controller.rb` | 수정 | `@assignee_workload` 쿼리 추가 (L41 이후 삽입) |
| `app/views/dashboard/index.html.erb` | 수정 | ROW 6 워크로드 위젯 추가 (L532 이후 삽입) |

---

## 모델 관계 확인

```
User ─── has_many :assignments ─── Assignment ─── belongs_to :order
     └── has_many :assigned_orders, through: :assignments, source: :order

Order ── has_many :assignments
      └─ has_many :assignees, through: :assignments, source: :user

Assignment: { user_id, order_id, role, created_at, updated_at }
User:        { id, name, email, role(enum), branch(enum) }
Order scope: :active → where.not(status: :delivered)
```

---

## FR-01: 컨트롤러 설계

### 삽입 위치
`dashboard_controller.rb` — `@expiring_visas` 쿼리 바로 위 (L42 직전)

### 쿼리 설계

```ruby
# 담당자별 워크로드 (활성 발주 담당 User Top10)
@assignee_workload = User
  .joins(:assignments => :order)
  .where(orders: { status: Order.statuses.except("delivered").values })
  .select(
    "users.id, users.name, users.role, users.branch,
     COUNT(orders.id)                                                          AS total_count,
     SUM(CASE WHEN orders.due_date < date('now')                         THEN 1 ELSE 0 END) AS overdue_count,
     SUM(CASE WHEN orders.due_date BETWEEN date('now') AND date('now', '+7 days') THEN 1 ELSE 0 END) AS urgent_count"
  )
  .group("users.id, users.name, users.role, users.branch")
  .order(Arel.sql("total_count DESC"))
  .limit(10)
```

**주의사항**:
- `Order.statuses.except("delivered").values` → `[0,1,2,3,4,5]` (delivered=6 제외)
- SQLite3 날짜 함수: `date('now')`, `date('now', '+7 days')`
- `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` — SQLite3 호환 집계

---

## FR-02: 뷰 설계

### 삽입 위치
`dashboard/index.html.erb` — 현재 마지막 `</div>` (ROW 5 종료 L531) 이후

### 위젯 레이아웃

```
ROW 6: 담당자별 워크로드 (전체 너비)
┌─────────────────────────────────────────────────────────────────┐
│ 담당자별 워크로드                    (총 N명 담당 중)            │
├─────────────────────────────────────────────────────────────────┤
│ [이니셜] 홍길동  manager  abu_dhabi │ ████████░░░░ │ 12건  3긴급 2지연 │
│ [이니셜] 김철수  member   seoul     │ ████░░░░░░░░ │  8건  1긴급 0지연 │
│ [이니셜] 이영희  member   abu_dhabi │ ██░░░░░░░░░░ │  4건  0긴급 1지연 │
│ ...                                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 컬럼 구성

| 컬럼 | 내용 | 크기 |
|------|------|------|
| 이니셜 아바타 | 2글자 이니셜, 색상 구분 | w-9 h-9 |
| 담당자 정보 | name + role 배지 + branch | flex-1 |
| 워크로드 바 | 최대값 대비 비율 | flex-1 |
| 총 건수 | bold 숫자 | w-12 |
| 긴급 배지 | 주황 `D-7` | shrink-0 조건부 |
| 지연 배지 | 빨강 `지연` | shrink-0 조건부 |

### 색상 규칙

```
행 배경:
  - overdue_count > 0  → bg-red-50/dark:bg-red-900/20 (지연 있음)
  - urgent_count > 0   → bg-orange-50/dark:bg-orange-900/20 (긴급 있음)
  - 기본              → hover:bg-gray-50

이니셜 아바타 색상 (idx % 5):
  0 → bg-blue-100 text-blue-700
  1 → bg-purple-100 text-purple-700
  2 → bg-green-100 text-green-700
  3 → bg-orange-100 text-orange-700
  4 → bg-pink-100 text-pink-700

역할 배지:
  admin   → bg-red-100 text-red-700
  manager → bg-blue-100 text-blue-700
  member  → bg-gray-100 text-gray-600
  viewer  → bg-gray-50 text-gray-400

지사 표시:
  abu_dhabi → "Abu Dhabi"
  seoul     → "Seoul"
```

### ERB 구조

```erb
<!-- ════════════════════════════════════════════════════════════
     ROW 6: 담당자별 워크로드
     ════════════════════════════════════════════════════════════ -->
<div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 mb-6">
  <div class="flex items-center justify-between px-5 py-3 border-b border-gray-100 dark:border-gray-700">
    <h3 class="text-sm font-semibold text-gray-900 dark:text-white">담당자별 워크로드</h3>
    <span class="text-xs text-gray-400 dark:text-gray-500">
      총 <%= @assignee_workload.sum(&:total_count) %>건 진행 중
    </span>
  </div>

  <% if @assignee_workload.empty? %>
    <div class="px-5 py-8 text-center text-sm text-gray-400 dark:text-gray-500">
      담당자가 배정된 발주 없음
    </div>
  <% else %>
    <% max_count = [@assignee_workload.map(&:total_count).max.to_i, 1].max %>
    <% avatar_colors = %w[bg-blue-100 text-blue-700 bg-purple-100 text-purple-700
                          bg-green-100 text-green-700 bg-orange-100 text-orange-700
                          bg-pink-100 text-pink-700] %>
    <% role_labels  = { "admin" => ["관리자", "bg-red-100 text-red-700"],
                        "manager" => ["매니저", "bg-blue-100 text-blue-700"],
                        "member"  => ["멤버",   "bg-gray-100 text-gray-600"],
                        "viewer"  => ["뷰어",   "bg-gray-50 text-gray-400"] } %>

    <div class="divide-y divide-gray-50 dark:divide-gray-700/50">
      <% @assignee_workload.each_with_index do |u, idx| %>
        <% row_bg = u.overdue_count.to_i > 0 ? "bg-red-50/50 dark:bg-red-900/10"
                  : u.urgent_count.to_i > 0  ? "bg-orange-50/50 dark:bg-orange-900/10"
                  : "" %>
        <% avatar_bg  = avatar_colors[(idx * 2) % 10] %>
        <% avatar_txt = avatar_colors[(idx * 2 + 1) % 10] %>
        <% role_info  = role_labels[u.role] || ["멤버", "bg-gray-100 text-gray-600"] %>
        <% branch_label = u.branch == "abu_dhabi" ? "Abu Dhabi" : "Seoul" %>

        <div class="flex items-center gap-4 px-5 py-3 <%= row_bg %> transition-colors">

          <%# 이니셜 아바타 %>
          <div class="w-9 h-9 rounded-full <%= avatar_bg %> <%= avatar_txt %> flex items-center justify-center text-sm font-bold shrink-0">
            <%= u.initials rescue u.name.to_s[0..1].upcase %>
          </div>

          <%# 담당자 정보 %>
          <div class="w-36 shrink-0">
            <p class="text-sm font-medium text-gray-900 dark:text-white truncate"><%= u.display_name %></p>
            <div class="flex items-center gap-1 mt-0.5">
              <span class="text-xs px-1.5 py-0.5 rounded-md font-medium <%= role_info[1] %>">
                <%= role_info[0] %>
              </span>
              <span class="text-xs text-gray-400 dark:text-gray-500"><%= branch_label %></span>
            </div>
          </div>

          <%# 워크로드 바 %>
          <div class="flex-1">
            <div class="flex items-center gap-2">
              <div class="flex-1 bg-gray-100 dark:bg-gray-700 rounded-full h-2">
                <div class="<%= u.overdue_count.to_i > 0 ? 'bg-red-400' : u.urgent_count.to_i > 0 ? 'bg-orange-400' : 'bg-blue-400' %> h-2 rounded-full transition-all duration-500"
                     style="width: <%= (u.total_count.to_i.to_f / max_count * 100).round %>%"></div>
              </div>
            </div>
          </div>

          <%# 건수 %>
          <div class="w-14 text-right shrink-0">
            <span class="text-sm font-bold text-gray-900 dark:text-white"><%= u.total_count %></span>
            <span class="text-xs text-gray-400 dark:text-gray-500">건</span>
          </div>

          <%# 긴급/지연 배지 %>
          <div class="flex items-center gap-1 w-20 shrink-0 justify-end">
            <% if u.urgent_count.to_i > 0 %>
              <span class="text-xs px-1.5 py-0.5 rounded-md bg-orange-100 dark:bg-orange-900/40 text-orange-700 dark:text-orange-400 font-medium">
                긴급 <%= u.urgent_count %>
              </span>
            <% end %>
            <% if u.overdue_count.to_i > 0 %>
              <span class="text-xs px-1.5 py-0.5 rounded-md bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-400 font-medium">
                지연 <%= u.overdue_count %>
              </span>
            <% end %>
          </div>

        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

---

## 구현 순서

1. `dashboard_controller.rb` — `@assignee_workload` 쿼리 삽입 (L42 직전)
2. `dashboard/index.html.erb` — ROW 6 위젯 추가 (L532 이후)
3. rubocop 체크
4. `/pdca analyze dashboard-kpi`

---

## 완료 기준

- [ ] 담당자별 워크로드 위젯 표시 (담당자 없으면 "배정된 발주 없음")
- [ ] 총/긴급/지연 건수 정확 집계
- [ ] 지연(빨강)/긴급(주황) 행 하이라이트
- [ ] 역할 배지, 지사 표시 정확
- [ ] rubocop 오류 없음
- [ ] Gap Analysis Match Rate ≥ 90%
