# team-ux Plan

## 1. Feature Overview

**Feature Name**: team-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (3 files)

### 1.1 Summary

팀/담당자 관리 페이지 UX 개선 —
현재 워크로드 카드 그리드와 개인 상세 페이지에 납기일 D-day 강조, Branch 필터링,
Admin 전용 Role/Branch 인라인 편집, 상태별 주문 탭 분류를 추가하여
팀 운영 효율성과 관리자 편의성을 높인다.

### 1.2 Current State (실측)

**`app/controllers/team_controller.rb`** (38줄):
- `index`: @members + @workloads(active/overdue/urgent/tasks) + @summary 계산 — 있음
- `show`: @member, @overdue_orders, @active_orders, @status_counts — 있음
- Branch별 그룹핑/필터링 없음
- Role/Branch 변경 액션 없음

**`app/views/team/index.html.erb`** (103줄):
- 팀 전체 통계 4카드(total/active/overdue/overloaded) — 있음
- 워크로드 카드 그리드(3열): 이름, 역할, 액티브/지연/긴급 건수, 진행률 바 — 있음
- 납기 D-day 표시 없음 (건수만 표시)
- Branch 필터 없음 (abu_dhabi/seoul 구분 없음)
- Role 변경 UI 없음

**`app/views/team/show.html.erb`** (85줄):
- 팀원 기본 정보 (이름, 역할, 이메일, 브랜치) — 있음
- 상태별 카운트 배지 행 — 있음
- 지연 주문 / 진행 주문 목록 (납기일 + 상태 뱃지) — 있음
- 상태별 탭 없음 (지연/진행만 구분)
- Admin 전용 편집 UI 없음

**문제점**:
1. **납기 D-day 없음**: 워크로드 카드에 "지연 N건"만 표시, 가장 급한 납기가 언제인지 불명
2. **Branch 필터 없음**: abu_dhabi/seoul 팀원 혼합 표시, 지사별 현황 파악 어려움
3. **Role 편집 불가**: Admin이 팀원 Role을 UI에서 변경할 수 없음 (콘솔 필요)
4. **상태 탭 없음**: show 페이지에서 all/overdue/active 탭 전환 불가

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **납기 D-day 강조**: 워크로드 카드에 가장 급한 납기일 D-N 배지 표시 |
| FR-02 | **Branch 필터**: index 페이지 상단에 All / Abu Dhabi / Seoul 탭 필터 |
| FR-03 | **Admin Role 편집**: Admin 로그인 시 워크로드 카드에 Role 변경 드롭다운 표시 |
| FR-04 | **상태별 탭**: show 페이지에 All / Overdue / Active 탭 전환 (JS 클라이언트 필터) |

### Out of Scope
- 담당자 일괄 재배정 (Drag & Drop)
- 팀원 신규 초대/삭제
- 주간/월간 워크로드 추이 차트

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/controllers/team_controller.rb` | Branch 필터 파라미터 처리 + Role 업데이트 액션 추가 |
| `app/views/team/index.html.erb` | Branch 탭 필터 + D-day 배지 + Admin Role 드롭다운 |
| `app/views/team/show.html.erb` | 상태별 탭 (JS 클라이언트 필터) |

### 3.2 Controller: Branch 필터 + Role 업데이트 (FR-02, FR-03)

```ruby
# index 액션 — Branch 필터
def index
  branch = params[:branch].presence
  @members = User.order(:branch, :name).includes(:assigned_orders, :tasks)
  @members = @members.where(branch: branch) if branch.present?
  # ... 기존 workloads/summary 계산
end

# Role 업데이트 액션 (Admin only)
def update_role
  authorize_admin!
  @member = User.find(params[:id])
  @member.update!(role: params[:role])
  redirect_to team_index_path, notice: "#{@member.name} 역할이 변경되었습니다."
end
```

라우트 추가:
```ruby
resources :team, only: [:index, :show] do
  member do
    patch :update_role
  end
end
```

### 3.3 View: 납기 D-day 배지 (FR-01)

워크로드 루프 내 `nearest_due` 계산 (컨트롤러에서 주입):

```ruby
# workloads 해시에 nearest_due 추가
nearest = active.min_by { |o| o.due_date || Date.new(9999) }
{
  ...,
  nearest_due: nearest&.due_date
}
```

ERB 뷰 — D-day 배지:
```erb
<%
  if w[:nearest_due]
    days = (w[:nearest_due] - Date.today).to_i
    d_color = days < 0 ? 'bg-red-100 text-red-700' :
              days <= 7 ? 'bg-orange-100 text-orange-700' : 'bg-green-100 text-green-700'
    d_label = days < 0 ? "D+#{days.abs}" : days == 0 ? 'D-Day' : "D-#{days}"
  end
%>
<% if w[:nearest_due] %>
  <span class="text-xs font-semibold px-2 py-0.5 rounded-full <%= d_color %>"><%= d_label %></span>
<% end %>
```

### 3.4 View: Branch 탭 필터 (FR-02)

```erb
<% branches = [['전체', nil], ['Abu Dhabi', 'abu_dhabi'], ['Seoul', 'seoul']] %>
<div class="flex gap-1 mb-4">
  <% branches.each do |label, val| %>
    <% active_tab = params[:branch] == val.to_s || (val.nil? && params[:branch].blank?) %>
    <%= link_to label,
          team_index_path(branch: val),
          class: "px-3 py-1.5 text-sm rounded-lg #{active_tab ? 'bg-primary text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}" %>
  <% end %>
</div>
```

### 3.5 View: Admin Role 드롭다운 (FR-03)

```erb
<% if current_user.admin? %>
  <%= form_with url: update_role_team_path(w[:user]), method: :patch, local: true do |f| %>
    <%= f.select :role,
          User.roles.keys.map { |r| [r.humanize, r] },
          { selected: w[:user].role },
          { class: "text-xs border rounded px-1 py-0.5",
            onchange: "this.form.submit()" } %>
  <% end %>
<% else %>
  <span class="text-xs text-gray-500"><%= w[:user].role&.humanize %></span>
<% end %>
```

### 3.6 View: 상태별 탭 — show 페이지 (FR-04)

JS 클라이언트 필터 (서버 요청 없이 탭 전환):

```javascript
function filterOrders(tab) {
  document.querySelectorAll('.order-row').forEach(function(row) {
    var show = tab === 'all' ||
               (tab === 'overdue' && row.dataset.overdue === 'true') ||
               (tab === 'active' && row.dataset.overdue !== 'true');
    row.style.display = show ? '' : 'none';
  });
  document.querySelectorAll('.tab-btn').forEach(function(btn) {
    btn.classList.toggle('active-tab', btn.dataset.tab === tab);
  });
}
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | 워크로드 카드에 가장 급한 납기일 D-day 배지 표시 (D+N/D-Day/D-N 색상 구분) |
| 2 | index 페이지 Branch 탭 필터 (All/Abu Dhabi/Seoul) 동작 |
| 3 | Admin 로그인 시 Role 드롭다운 표시 및 변경 동작 |
| 4 | show 페이지 All/Overdue/Active 탭 전환 (JS 클라이언트 필터) |
| 5 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `User.roles` enum — 기존 존재 (admin/manager/member/viewer)
- `User#branch` — 기존 존재 (abu_dhabi/seoul)
- `assigned_orders` 연관 — 기존 존재
- `authorize_admin!` before_action — 기존 패턴 참조

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
