# Design: team-ux

## 개요

팀 현황 UX 강화 — 통계 바(FR-01) + 워크로드 카드 강화(FR-02) + 팀원 상세 강화(FR-03)

- **Plan**: `docs/01-plan/features/team-ux.plan.md`
- **작성일**: 2026-02-28

---

## 실측 확인 사항

| 항목 | 값 |
|------|-----|
| `Order.scope :active` | `where.not(status: :delivered)` |
| `Order.scope :overdue` | `where("due_date < ?", Date.today).where.not(status: :delivered)` |
| `Order.scope :urgent` | `where("due_date <= ?", 7.days.from_now).where.not(status: :delivered)` |
| `Task.scope :pending` | `where(completed: false)` |
| `User#assigned_orders` | `has_many :assigned_orders, through: :assignments, source: :order` |
| `User#display_name` | L39 정의됨 |
| `User#initials` | L43 정의됨 |
| `openOrderDrawer(id, title, path)` | `layouts/application.html.erb` L152 전역 |
| `priority_badge(order)` | `application_helper.rb` L35 |
| `due_badge(order)` | `application_helper.rb` L19 |
| `status_badge(order)` | `application_helper.rb` L47 |

---

## 변경 파일

| 파일 | 변경 | 내용 |
|------|------|------|
| `app/controllers/team_controller.rb` | 수정 | overdue/urgent 카운트 + @summary + show 강화 |
| `app/views/team/index.html.erb` | 수정 | FR-01 통계 바 + FR-02 카드 강화 |
| `app/views/team/show.html.erb` | 수정 | FR-03 지연 섹션 + 배지 + 드로어 연동 |

---

## FR-01 + FR-02: 컨트롤러 index 변경

```ruby
class TeamController < ApplicationController
  def index
    @members = User.order(:branch, :name).includes(:assigned_orders, :tasks)
    today = Date.today

    @workloads = @members.map do |u|
      active = u.assigned_orders.active.to_a
      {
        user:           u,
        active_orders:  active.count,
        tasks_pending:  u.tasks.pending.count,
        overdue_orders: active.count { |o| o.due_date && o.due_date < today },
        urgent_orders:  active.count { |o| o.due_date && o.due_date >= today && o.due_date <= today + 7 }
      }
    end

    @summary = {
      total_members:  @members.count,
      total_active:   @workloads.sum { |w| w[:active_orders] },
      total_overdue:  @workloads.sum { |w| w[:overdue_orders] },
      overloaded:     @workloads.count { |w| w[:active_orders] >= 8 }
    }
  end

  def show
    @member        = User.find(params[:id])
    @overdue_orders = @member.assigned_orders.overdue.by_due_date
                             .includes(:client, :project)
    @active_orders  = @member.assigned_orders.active
                             .where("due_date >= ? OR due_date IS NULL", Date.today)
                             .by_due_date.limit(20)
                             .includes(:client, :project)
    @status_counts  = @member.assigned_orders.group(:status).count
  end
end
```

---

## FR-01: 팀 전체 통계 바 ERB

헤더 `</div>` 직후, 워크로드 그리드 위:

```erb
<%# FR-01: 팀 전체 통계 바 %>
<div class="grid grid-cols-4 gap-3">
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4 text-center">
    <p class="text-2xl font-bold text-gray-900 dark:text-white"><%= @summary[:total_members] %></p>
    <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">총 팀원</p>
  </div>
  <div class="bg-blue-50 dark:bg-blue-900/20 rounded-xl border border-blue-100 dark:border-blue-800 p-4 text-center">
    <p class="text-2xl font-bold text-blue-600 dark:text-blue-400"><%= @summary[:total_active] %></p>
    <p class="text-xs text-blue-500 dark:text-blue-400 mt-1">총 진행 주문</p>
  </div>
  <div class="bg-red-50 dark:bg-red-900/20 rounded-xl border border-red-100 dark:border-red-800 p-4 text-center">
    <p class="text-2xl font-bold text-red-600 dark:text-red-400"><%= @summary[:total_overdue] %></p>
    <p class="text-xs text-red-500 dark:text-red-400 mt-1">지연 주문</p>
  </div>
  <div class="bg-orange-50 dark:bg-orange-900/20 rounded-xl border border-orange-100 dark:border-orange-800 p-4 text-center">
    <p class="text-2xl font-bold text-orange-600 dark:text-orange-400"><%= @summary[:overloaded] %></p>
    <p class="text-xs text-orange-500 dark:text-orange-400 mt-1">과부하 팀원</p>
  </div>
</div>
```

---

## FR-02: 워크로드 카드 강화 ERB

기존 카드 구조 유지, 다음 항목 변경:

### 1. 카드 루트 div — 과부하 경고 테두리

```erb
<%# 기존 %>
<%= link_to team_path(user), class: "bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-5 ..." do %>

<%# 변경: 과부하 시 border-red-300 %>
<% is_overloaded = w[:active_orders] >= 8 %>
<%= link_to team_path(user),
    class: "bg-white dark:bg-gray-800 rounded-xl border p-5 hover:shadow-md transition-all block
            #{is_overloaded ? 'border-red-300 dark:border-red-700' : 'border-gray-200 dark:border-gray-700 hover:border-primary/30'}" do %>
```

### 2. 이름 영역 — 과부하 배지 추가

```erb
<div class="flex items-center justify-between mb-4">
  <div class="flex items-center gap-3">
    <div class="w-10 h-10 rounded-full bg-primary/10 ... ">
      <%= user.initials %>
    </div>
    <div class="min-w-0">
      <p class="font-semibold text-gray-900 dark:text-white truncate"><%= user.display_name %></p>
      <div class="flex items-center gap-2 mt-0.5">
        <%# 역할 배지 (기존) %>
        ...
      </div>
    </div>
  </div>
  <%# FR-02: 과부하 경고 배지 %>
  <% if is_overloaded %>
    <span class="text-xs font-semibold bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400 px-2 py-0.5 rounded-full shrink-0">
      과부하
    </span>
  <% end %>
</div>
```

### 3. 숫자 카드 — 4개로 확장 (지연 + 긴급 추가)

```erb
<%# 기존: 2개 (진행 중 / 대기 태스크) %>
<%# 변경: 4개 (진행 중 / 지연 / 긴급 / 대기 태스크) %>
<div class="grid grid-cols-4 gap-2">
  <div class="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-2 text-center">
    <p class="text-xl font-bold text-gray-900 dark:text-white"><%= w[:active_orders] %></p>
    <p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">진행</p>
  </div>
  <div class="bg-red-50 dark:bg-red-900/20 rounded-lg p-2 text-center">
    <p class="text-xl font-bold text-red-600 dark:text-red-400"><%= w[:overdue_orders] %></p>
    <p class="text-xs text-red-500 dark:text-red-400 mt-0.5">지연</p>
  </div>
  <div class="bg-orange-50 dark:bg-orange-900/20 rounded-lg p-2 text-center">
    <p class="text-xl font-bold text-orange-600 dark:text-orange-400"><%= w[:urgent_orders] %></p>
    <p class="text-xs text-orange-500 dark:text-orange-400 mt-0.5">D-7</p>
  </div>
  <div class="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-2 text-center">
    <p class="text-xl font-bold text-gray-900 dark:text-white"><%= w[:tasks_pending] %></p>
    <p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5">태스크</p>
  </div>
</div>
```

### 4. 워크로드 바 — 색상 기준 개선

```erb
<%# 기존: 50% / 80% 기준 %>
<%# 변경: 4건(40%) / 7건(70%) 기준 %>
<% load_pct = [[w[:active_orders] * 10, 100].min, 0].max %>
<div class="h-full rounded-full transition-all
            <%= w[:active_orders] >= 8 ? 'bg-red-400' :
                w[:active_orders] >= 5 ? 'bg-orange-400' : 'bg-green-400' %>"
     style="width: <%= load_pct %>%"></div>
```

---

## FR-03: 팀원 상세 (show.html.erb) 강화

### 1. 지연 주문 섹션 (진행 중 주문 위에 삽입)

```erb
<%# FR-03: 지연 주문 섹션 %>
<% if @overdue_orders.any? %>
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-red-200 dark:border-red-800 overflow-hidden">
    <div class="px-5 py-4 border-b border-red-100 dark:border-red-800 bg-red-50 dark:bg-red-900/20">
      <h2 class="text-sm font-semibold text-red-700 dark:text-red-400">
        지연 주문 (<%= @overdue_orders.count %>건)
      </h2>
    </div>
    <div class="divide-y divide-gray-50 dark:divide-gray-700">
      <% @overdue_orders.each do |order| %>
        <div class="flex items-center justify-between px-5 py-3
                    hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors cursor-pointer"
             onclick="openOrderDrawer(<%= order.id %>, <%= order.title.to_json %>, '<%= order_path(order) %>')">
          <div class="min-w-0">
            <p class="text-sm font-medium text-gray-900 dark:text-white truncate"><%= order.title %></p>
            <div class="flex items-center gap-1.5 mt-0.5">
              <% if order.client %>
                <span class="text-xs text-blue-600 dark:text-blue-400"><%= order.client.name %></span>
              <% elsif order.customer_name.present? %>
                <span class="text-xs text-gray-500 dark:text-gray-400"><%= order.customer_name %></span>
              <% end %>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <%= status_badge(order) %>
            <%= priority_badge(order) %>
            <%= due_badge(order) %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

### 2. 진행 중 주문 섹션 — 배지 + 드로어 연동

```erb
<%# 기존: link_to "보기" + status 텍스트 배지만 %>
<%# 변경: onclick openOrderDrawer + status_badge + priority_badge + due_badge %>
<div class="flex items-center justify-between px-5 py-3
            hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors cursor-pointer"
     onclick="openOrderDrawer(<%= order.id %>, <%= order.title.to_json %>, '<%= order_path(order) %>')">
  <div class="min-w-0">
    <p class="text-sm font-medium text-gray-900 dark:text-white truncate"><%= order.title %></p>
    <div class="flex items-center gap-1.5 mt-0.5">
      <% if order.client %>
        <span class="text-xs text-blue-600 dark:text-blue-400"><%= order.client.name %></span>
      <% elsif order.customer_name.present? %>
        <span class="text-xs text-gray-500 dark:text-gray-400"><%= order.customer_name %></span>
      <% end %>
      <% if order.project %>
        <span class="text-xs text-green-600 dark:text-green-400"><%= order.project.name %></span>
      <% end %>
    </div>
  </div>
  <div class="flex items-center gap-2 shrink-0">
    <%= status_badge(order) %>
    <%= priority_badge(order) %>
    <%= due_badge(order) %>
  </div>
</div>
```

---

## 구현 순서

1. `team_controller.rb` — index (@workloads 확장 + @summary) + show (@overdue_orders + includes)
2. `team/index.html.erb` — FR-01 통계 바 삽입
3. `team/index.html.erb` — FR-02 카드 강화 (과부하 배지 + 4개 숫자 + 워크로드 바 색상)
4. `team/show.html.erb` — FR-03 지연 섹션 + 진행 중 주문 배지 + 드로어 연동
5. rubocop 체크

---

## 완료 기준

- [ ] 팀 통계 바 4개 카드 (총 팀원/총 진행/지연/과부하)
- [ ] 팀원 카드 4개 숫자 (진행/지연/D-7/태스크)
- [ ] active ≥ 8 → "과부하" 배지 + 빨간 테두리
- [ ] 팀원 상세 — 지연 주문 별도 섹션 (빨간 헤더)
- [ ] 팀원 상세 — status_badge + priority_badge + due_badge
- [ ] 팀원 상세 — openOrderDrawer 연동
- [ ] Gap Analysis Match Rate ≥ 90%
