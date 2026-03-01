# Design: employee-profile-ux

- **Feature**: employee-profile-ux
- **Plan**: docs/01-plan/features/employee-profile-ux.plan.md
- **Created**: 2026-03-01

---

## 1. 아키텍처 개요

```
[index.html.erb]          [show.html.erb]
  FR-01 아바타            FR-01 아바타 (64px)
  FR-06 부서/직책 필터    FR-02 탭 URL 직링크
  FR-07 직책 컬럼         FR-03 연락처 원클릭
  FR-08 Quick Action      FR-04 빈 상태 + CTA
                          FR-05 재직기간 포맷

[employee.rb]
  FR-01 avatar_color(nationality)
  FR-05 tenure_label

[employees_controller.rb]
  FR-06 job_title 필터 파라미터 추가
```

---

## 2. 상세 설계

### FR-01: 직원 아바타 컴포넌트

**모델 헬퍼 (app/models/employee.rb)**
```ruby
# 국적별 배경색 (CSS 클래스)
AVATAR_COLORS = {
  "KR" => "bg-blue-500",
  "AE" => "bg-emerald-500",
  "PH" => "bg-yellow-500",
  "IN" => "bg-orange-500",
  "PK" => "bg-green-600",
  "EG" => "bg-amber-600",
  "US" => "bg-indigo-500",
  "GB" => "bg-violet-500",
  "JP" => "bg-rose-500",
  "CN" => "bg-red-500",
}.freeze

def avatar_color
  AVATAR_COLORS[nationality] || "bg-gray-500"
end

def initials
  name.split.map(&:first).first(2).join.upcase
end
```

**show 헤더 아바타 (64px)**
```html
<div class="w-16 h-16 rounded-full <%= @employee.avatar_color %>
     flex items-center justify-center text-white text-xl font-bold flex-shrink-0">
  <%= @employee.initials %>
</div>
```

**index 테이블 미니 아바타 (32px)**
```html
<div class="w-8 h-8 rounded-full <%= emp.avatar_color %>
     flex items-center justify-center text-white text-xs font-bold flex-shrink-0">
  <%= emp.initials %>
</div>
```

---

### FR-02: 탭 URL 직링크

**Alpine.js 초기화** — URL params에서 탭 초기값 읽기
```html
<div x-data="{
  tab: new URLSearchParams(window.location.search).get('tab') || 'info',
  switchTab(t) {
    this.tab = t;
    const url = new URL(window.location);
    url.searchParams.set('tab', t);
    window.history.pushState({}, '', url);
  }
}">
```

**탭 버튼** — `@click="switchTab('visas')"` 형태로 교체
```html
<button @click="switchTab('info')"
        :class="tab==='info' ? 'border-primary text-primary' : 'border-transparent text-gray-500 ...'"
        class="py-3 border-b-2 text-sm font-medium transition-colors">기본정보</button>
```

**지원 탭 값**: `info`, `visas`, `contracts`, `assignments`, `certs`

---

### FR-03: 연락처 원클릭 액션

**기본정보 탭 연락처 필드 교체**
```html
<!-- 전화번호 -->
<div>
  <dt class="text-gray-500 dark:text-gray-400">전화번호</dt>
  <dd class="mt-1">
    <% if @employee.phone.present? %>
      <div class="flex items-center gap-2">
        <a href="tel:<%= @employee.phone %>"
           class="font-medium text-gray-900 dark:text-white hover:text-primary flex items-center gap-1">
          <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 13.6 19.79 19.79 0 0 1 1.63 5a2 2 0 0 1 1.99-2.18h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L7.91 10.1a16 16 0 0 0 6 6l.92-.92a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 17.58z"/>
          </svg>
          <%= @employee.phone %>
        </a>
        <!-- WhatsApp 딥링크 -->
        <a href="https://wa.me/<%= @employee.phone.gsub(/\D/, '') %>"
           target="_blank" rel="noopener"
           class="w-6 h-6 flex items-center justify-center rounded-full bg-green-50 dark:bg-green-900/30 text-green-600 dark:text-green-400 hover:bg-green-100"
           title="WhatsApp">
          <!-- WhatsApp SVG icon -->
          <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="currentColor">
            <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z"/>
          </svg>
        </a>
      </div>
    <% else %>
      <span class="font-medium text-gray-400 dark:text-gray-500">-</span>
    <% end %>
  </dd>
</div>
```

**이메일** — Employee 모델에 `email` 컬럼 유무 확인 필요
- 있으면: `mailto:` 링크
- 없으면: `user.email` 연결 표시

---

### FR-04: 빈 상태(Empty State) 개선

**각 탭 빈 상태 공통 패턴**
```html
<div class="flex flex-col items-center justify-center py-12 gap-3">
  <!-- 탭별 아이콘 (비자: document, 계약: file-text, 배정: map-pin, 자격증: award) -->
  <svg class="w-10 h-10 text-gray-200 dark:text-gray-700" .../>
  <p class="text-sm text-gray-400 dark:text-gray-500">등록된 비자가 없습니다.</p>
  <%= link_to new_employee_visa_path(@employee),
      class: "inline-flex items-center gap-1 text-sm text-primary border border-primary/30
              rounded-lg px-3 py-1.5 hover:bg-primary/5 transition-colors" do %>
    <svg class="w-3.5 h-3.5" ...>+</svg>
    비자 추가
  <% end %>
</div>
```

| 탭 | 아이콘 | 문구 | CTA 링크 |
|---|---|---|---|
| 비자 | file-text | 등록된 비자가 없습니다. | new_employee_visa_path |
| 계약 | briefcase | 등록된 계약이 없습니다. | new_employee_employment_contract_path |
| 현장 배정 | map-pin | 현장 배정 이력이 없습니다. | new_employee_employee_assignment_path |
| 자격증 | award | 등록된 자격증이 없습니다. | new_employee_certification_path |

---

### FR-05: 재직기간 포맷 개선

**모델 헬퍼 (app/models/employee.rb)**
```ruby
def tenure_label
  return nil unless hire_date
  total_days = ((termination_date || Date.today) - hire_date).to_i
  years  = total_days / 365
  months = (total_days % 365) / 30
  if years > 0
    "#{years}년 #{months}개월"
  elsif months > 0
    "#{months}개월"
  else
    "#{total_days}일"
  end
end
```

**show KPI 카드 교체**
```html
<p class="text-xl font-bold text-gray-900 dark:text-white mt-1">
  <%= @employee.tenure_label %>
</p>
<p class="text-xs text-gray-400 dark:text-gray-500">
  <%= @employee.hire_date.strftime("%Y.%m.%d") %> 입사 (<%= @employee.tenure_days %>일)
</p>
```

---

### FR-06: index 필터 — 직책 추가

**컨트롤러** — `department` 필터는 이미 존재. `job_title` 필터 추가
```ruby
# employees_controller.rb index 액션
@employees = @employees.where(job_title: params[:job_title]) if params[:job_title].present?
```

**뷰 필터 폼** — 부서 select + 직책 select 추가
```html
<!-- 부서 필터 (신규) -->
<%= f.select :department,
    [["전체 부서", ""]] + Department.active.by_sort.map { |d| [d.name, d.id] },
    { selected: params[:department] },
    class: "border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800
            text-gray-900 dark:text-white rounded-lg px-3 py-2 text-sm
            focus:outline-none focus:border-primary" %>

<!-- 직책 필터 (신규) -->
<%= f.select :job_title,
    [["전체 직책", ""]] + JobTitle.active.by_sort.map { |jt| [jt.name, jt.name] },
    { selected: params[:job_title] },
    class: "border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800
            text-gray-900 dark:text-white rounded-lg px-3 py-2 text-sm
            focus:outline-none focus:border-primary" %>
```

---

### FR-07: index 테이블 — 직책 컬럼

**기존 "국적/부서" 셀에 직책 추가**
```html
<td class="px-4 py-3 text-sm text-gray-600 dark:text-gray-400">
  <div><%= emp.nationality_label %></div>
  <div class="text-xs text-gray-400 dark:text-gray-500">
    <%= [emp.department&.name, emp.job_title.presence].compact.join(" · ") %>
  </div>
</td>
```

---

### FR-08: index 행 Quick Action

**기존 "상세" 링크 → 호버 시 [상세 / 수정] 버튼**
```html
<td class="px-4 py-3 text-right">
  <div class="flex items-center justify-end gap-2">
    <%= link_to "상세", emp,
        class: "text-xs text-primary hover:underline" %>
    <% if current_user.manager? || current_user.admin? %>
      <%= link_to "수정", edit_employee_path(emp),
          class: "text-xs text-gray-400 dark:text-gray-500 hover:text-gray-700
                  dark:hover:text-gray-300 opacity-0 group-hover:opacity-100 transition-opacity" %>
    <% end %>
  </div>
</td>
```
- `<tr>` 태그에 `class="... group"` 추가 필요

---

## 3. 구현 순서

```
Step 1: app/models/employee.rb
  - avatar_color() 메서드
  - tenure_label() 메서드
  - AVATAR_COLORS 상수

Step 2: app/controllers/employees_controller.rb
  - job_title 필터 파라미터 추가 (1줄)

Step 3: app/views/employees/show.html.erb
  - FR-01: 헤더 아바타 (64px)
  - FR-02: 탭 URL 직링크 (Alpine.js switchTab)
  - FR-03: 전화번호 tel: + WhatsApp 링크
  - FR-04: 4개 탭 빈 상태 CTA
  - FR-05: tenure_label KPI 카드

Step 4: app/views/employees/index.html.erb
  - FR-01: 미니 아바타 (32px)
  - FR-06: 직책 필터 select
  - FR-07: 직책 컬럼 (국적/부서 셀에 병합)
  - FR-08: group hover Quick Action
```

---

## 4. 변경 파일 최종 목록

| 파일 | FR | 변경 내용 |
|------|-----|---------|
| `app/models/employee.rb` | FR-01, FR-05 | `avatar_color`, `tenure_label`, `AVATAR_COLORS` |
| `app/controllers/employees_controller.rb` | FR-06 | `job_title` 필터 1줄 추가 |
| `app/views/employees/show.html.erb` | FR-01~05 | 헤더, 탭, 연락처, 빈상태, KPI |
| `app/views/employees/index.html.erb` | FR-01, 06~08 | 아바타, 필터, 직책컬럼, Quick Action |

---

## 5. 품질 기준

- Dark mode: 모든 신규 요소 `dark:` 클래스 포함
- 접근성: 아이콘 링크에 `title` 속성
- 기존 기능: 필터/검색/비자만료 배너 유지
- 권한: Quick Action 수정 버튼은 manager/admin만 표시
