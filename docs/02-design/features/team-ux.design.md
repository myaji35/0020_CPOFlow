# team-ux Design

## 1. Overview

**Feature**: team-ux
**Phase**: Design
**Created**: 2026-02-28
**References**: `docs/01-plan/features/team-ux.plan.md`

팀/담당자 관리 페이지 UX 개선 — 납기 D-day 배지, Branch 탭 필터, Admin Role 편집, 상태별 탭.

---

## 2. Architecture

### 2.1 Data Flow

```
TeamController#index
  ↓ params[:branch] 필터 적용
@members (User, branch 필터)
  ↓ @workloads 계산
    - nearest_due: active 중 가장 가까운 due_date
    - active/overdue/urgent/tasks 기존 유지
  ↓ ERB 렌더링:
    - Branch 탭 필터 (All/Abu Dhabi/Seoul)
    - 워크로드 카드: D-day 배지 + Admin Role 드롭다운
    - 링크 클릭 → TeamController#show

TeamController#show
  ↓ @all_orders = overdue + active 합산
  ↓ ERB 렌더링:
    - All/Overdue/Active 탭 (JS 클라이언트 필터)
    - data-overdue 속성으로 탭 분류

TeamController#update_role (PATCH /team/:id/update_role)
  ↓ Admin 권한 확인
  ↓ user.update!(role:)
  ↓ redirect team_index_path
```

### 2.2 Files to Modify

| File | 변경 내용 |
|------|-----------|
| `config/routes.rb` | update_role 라우트 추가 |
| `app/controllers/team_controller.rb` | Branch 필터 + nearest_due + update_role 액션 |
| `app/views/team/index.html.erb` | Branch 탭 + D-day 배지 + Admin Role 드롭다운 |
| `app/views/team/show.html.erb` | All/Overdue/Active 탭 (JS 필터) |

---

## 3. Detailed Design

### 3.1 Routes 추가

```ruby
# config/routes.rb
get  '/team',     to: 'team#index',       as: 'team_index'
get  '/team/:id', to: 'team#show',        as: 'team'
patch '/team/:id/update_role', to: 'team#update_role', as: 'update_role_team'
```

### 3.2 Controller: Branch 필터 + nearest_due + update_role (FR-01, FR-02, FR-03)

```ruby
class TeamController < ApplicationController
  def index
    branch = params[:branch].presence
    scope  = User.order(:branch, :name).includes(:assigned_orders, :tasks)
    scope  = scope.where(branch: branch) if branch.present?
    @members = scope

    today = Date.today

    @workloads = @members.map do |u|
      active  = u.assigned_orders.active.to_a
      nearest = active.select { |o| o.due_date.present? }
                      .min_by { |o| o.due_date }
      {
        user:           u,
        active_orders:  active.count,
        tasks_pending:  u.tasks.pending.count,
        overdue_orders: active.count { |o| o.due_date && o.due_date < today },
        urgent_orders:  active.count { |o| o.due_date && o.due_date >= today && o.due_date <= today + 7 },
        nearest_due:    nearest&.due_date
      }
    end

    @summary = {
      total_members: @members.count,
      total_active:  @workloads.sum { |w| w[:active_orders] },
      total_overdue: @workloads.sum { |w| w[:overdue_orders] },
      overloaded:    @workloads.count { |w| w[:active_orders] >= 8 }
    }
  end

  def show
    @member         = User.find(params[:id])
    @overdue_orders = @member.assigned_orders.overdue.by_due_date
                             .includes(:client, :project)
    @active_orders  = @member.assigned_orders.active
                             .where("due_date >= ? OR due_date IS NULL", Date.today)
                             .by_due_date.limit(20)
                             .includes(:client, :project)
    @status_counts  = @member.assigned_orders.group(:status).count
  end

  def update_role
    redirect_to team_index_path, alert: "권한이 없습니다." and return unless current_user.admin?
    @member = User.find(params[:id])
    @member.update!(role: params[:role])
    redirect_to team_index_path, notice: "#{@member.display_name} 역할이 변경되었습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to team_index_path, alert: "변경 실패: #{e.message}"
  end
end
```

### 3.3 View index.html.erb: Branch 탭 필터 (FR-02)

헤더 하단, 통계 카드 상단에 탭 배치:

```erb
<%# Branch 탭 필터 %>
<% branch_tabs = [['전체', nil], ['Abu Dhabi', 'abu_dhabi'], ['Seoul', 'seoul']] %>
<div class="flex gap-1">
  <% branch_tabs.each do |label, val| %>
    <% is_active = params[:branch].to_s == val.to_s || (val.nil? && params[:branch].blank?) %>
    <%= link_to label,
          team_index_path(branch: val),
          class: "px-3 py-1.5 text-sm rounded-lg font-medium transition-colors " \
                 "#{is_active ? 'bg-primary text-white' : 'bg-white dark:bg-gray-800 text-gray-600 dark:text-gray-300 border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700'}" %>
  <% end %>
</div>
```

### 3.4 View index.html.erb: D-day 배지 (FR-01)

워크로드 카드 헤더 우측, 과부하 배지와 같은 줄에 배치:

```erb
<%
  today = Date.today
  if w[:nearest_due]
    days    = (w[:nearest_due] - today).to_i
    d_label = days < 0  ? "D+#{days.abs}" :
              days == 0 ? 'D-Day'          : "D-#{days}"
    d_color = days < 0  ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400' :
              days <= 7 ? 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400' :
                          'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
  end
%>
<%# 카드 헤더 우측 배지 영역 %>
<div class="flex flex-col items-end gap-1 shrink-0">
  <% if is_overloaded %>
    <span class="text-xs font-semibold bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400 px-2 py-0.5 rounded-full">
      과부하
    </span>
  <% end %>
  <% if w[:nearest_due] %>
    <span class="text-xs font-semibold px-2 py-0.5 rounded-full <%= d_color %>"><%= d_label %></span>
  <% end %>
</div>
```

### 3.5 View index.html.erb: Admin Role 드롭다운 (FR-03)

워크로드 바 하단에 추가:

```erb
<%# Admin Role 편집 (Admin 전용) %>
<% if current_user.admin? %>
  <div class="mt-3 pt-3 border-t border-gray-100 dark:border-gray-700 flex items-center justify-between">
    <span class="text-xs text-gray-400 dark:text-gray-500">역할 변경</span>
    <%= form_with url: update_role_team_path(user), method: :patch, local: true do |f| %>
      <%= f.select :role,
            [['뷰어', 'viewer'], ['멤버', 'member'], ['매니저', 'manager'], ['관리자', 'admin']],
            { selected: user.role },
            { class:    "text-xs border border-gray-200 dark:border-gray-600 rounded px-1.5 py-0.5 " \
                        "bg-white dark:bg-gray-700 text-gray-700 dark:text-gray-300",
              onchange: "this.form.requestSubmit()" } %>
    <% end %>
  </div>
<% end %>
```

### 3.6 View show.html.erb: 상태별 탭 (FR-04)

헤더 하단에 탭 버튼 + JS 클라이언트 필터:

```html
<!-- 탭 버튼 -->
<div class="flex gap-1" id="order-tabs">
  <button class="tab-btn active-tab px-3 py-1.5 text-sm rounded-lg font-medium"
          data-tab="all" onclick="filterOrders('all')">
    전체 (<span id="count-all">N</span>)
  </button>
  <button class="tab-btn px-3 py-1.5 text-sm rounded-lg font-medium"
          data-tab="overdue" onclick="filterOrders('overdue')">
    지연 (<span id="count-overdue">N</span>)
  </button>
  <button class="tab-btn px-3 py-1.5 text-sm rounded-lg font-medium"
          data-tab="active" onclick="filterOrders('active')">
    진행 (<span id="count-active">N</span>)
  </button>
</div>

<!-- 주문 행: data-overdue 속성으로 구분 -->
<div class="order-row" data-overdue="true">...</div>
<div class="order-row" data-overdue="false">...</div>

<script>
function filterOrders(tab) {
  var rows = document.querySelectorAll('.order-row');
  rows.forEach(function(row) {
    var overdue = row.dataset.overdue === 'true';
    var show = tab === 'all' || (tab === 'overdue' && overdue) || (tab === 'active' && !overdue);
    row.style.display = show ? '' : 'none';
  });
  document.querySelectorAll('.tab-btn').forEach(function(btn) {
    var isActive = btn.dataset.tab === tab;
    btn.classList.toggle('bg-primary', isActive);
    btn.classList.toggle('text-white', isActive);
    btn.classList.toggle('bg-white', !isActive);
    btn.classList.toggle('dark:bg-gray-800', !isActive);
    btn.classList.toggle('text-gray-600', !isActive);
    btn.classList.toggle('dark:text-gray-300', !isActive);
    btn.classList.toggle('border', !isActive);
    btn.classList.toggle('border-gray-200', !isActive);
  });
}
// 초기화
document.addEventListener('DOMContentLoaded', function() {
  var all   = document.querySelectorAll('.order-row').length;
  var od    = document.querySelectorAll('.order-row[data-overdue="true"]').length;
  var act   = document.querySelectorAll('.order-row[data-overdue="false"]').length;
  document.getElementById('count-all').textContent     = all;
  document.getElementById('count-overdue').textContent = od;
  document.getElementById('count-active').textContent  = act;
});
</script>
```

---

## 4. UI Mockup

### 4.1 index 페이지 (개선 후)

```
┌──────────────────────────────────────────────────────────┐
│ 팀 현황                                                   │
│ [전체] [Abu Dhabi] [Seoul]   ← Branch 탭 필터             │
├──────────────────────────────────────────────────────────┤
│ [5 총팀원] [12 진행] [3 지연] [1 과부하]                  │
├──────────────────────────────────────────────────────────┤
│ ┌─────────────────────┐  ┌─────────────────────┐         │
│ │ 홍길동  [매니저]    │  │ 김민준  [멤버]      │         │
│ │ abu_dhabi    [D-3] ←┤  │ seoul       [D-12]  │         │
│ │ [진행:5][지연:2]... │  │ [진행:3][지연:0]... │         │
│ │ ────────────────── │  │ ─────────────────── │         │
│ │ 역할변경: [매니저▼] │  │ 역할변경: [멤버▼]   │         │
│ └─────────────────────┘  └─────────────────────┘         │
└──────────────────────────────────────────────────────────┘
```

### 4.2 show 페이지 (개선 후)

```
┌──────────────────────────────────────────────────────┐
│ ← 홍길동  [매니저]  hong@atozone.com                 │
├──────────────────────────────────────────────────────┤
│ [inbox:1] [reviewing:2] [confirmed:3] [procuring:1] │
├──────────────────────────────────────────────────────┤
│ [전체(7)] [지연(2)] [진행(5)]   ← 탭 필터            │
├──────────────────────────────────────────────────────┤
│ Valve Assembly    ABC Corp · Site-A   confirmed D+3 │
│ Pump Unit         XYZ Ltd             procuring D-2  │
│ Cable Tray        ...                 reviewing D-15  │
└──────────────────────────────────────────────────────┘
```

---

## 5. Implementation Order

1. `config/routes.rb` — `update_role_team` PATCH 라우트 추가
2. `app/controllers/team_controller.rb` — Branch 필터 + nearest_due + update_role 액션
3. `app/views/team/index.html.erb` — Branch 탭 필터 추가 (헤더 하단)
4. `app/views/team/index.html.erb` — D-day 배지 추가 (카드 헤더 우측)
5. `app/views/team/index.html.erb` — Admin Role 드롭다운 추가 (카드 하단)
6. `app/views/team/show.html.erb` — 전체/지연/진행 탭 + JS 필터 + data-overdue 속성

---

## 6. Completion Criteria

| # | Criteria | 검증 방법 |
|---|----------|-----------|
| 1 | 워크로드 카드에 nearest_due D-day 배지 표시 | 뷰 HTML 확인 |
| 2 | Branch 탭 필터(All/Abu Dhabi/Seoul) 동작 | 링크 params 확인 |
| 3 | Admin Role 드롭다운 → PATCH update_role 전송 | 라우트+컨트롤러 확인 |
| 4 | show 탭(전체/지연/진행) JS 클라이언트 필터 | JS filterOrders 확인 |
| 5 | Gap Analysis Match Rate >= 90% | gap-detector |

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
