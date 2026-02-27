# Design: client-supplier-management

> 발주처·거래처·현장 심층 관리 고도화 — 상세 구현 설계

---

## 현황 재분석 (코드베이스 확인 결과)

Plan 단계에서 예상했던 것보다 **이미 구현된 부분이 많음**:

| 항목 | 실제 상태 |
|------|---------|
| 사이드바 Client/Supplier/Project 링크 | ✅ 이미 구현 (`_sidebar.html.erb` 27~29행) |
| Order 폼 Client/Supplier/Project select | ✅ 이미 구현 (드롭다운 select) |
| Client show 탭 (담당자/프로젝트/거래이력) | ✅ 이미 구현 |
| Supplier show 탭 (담당자/납품품목/이력) | ✅ 이미 구현 |
| 거래이력 필터 (기간/정렬) | ✅ 이미 구현 |
| 납기일 D-day 색상 코딩 | ✅ 이미 구현 |
| Client 리스크 등급 계산 | ✅ 이미 구현 |
| Supplier 성과 등급 계산 | ✅ 이미 구현 |
| Project 예산 집행률 progress bar | ✅ Client show 탭에 구현 |

### 실제 GAP (구현 필요)

| GAP | FR | 상세 |
|-----|----|------|
| Client 거래이력 월별 Chart.js 차트 없음 | FR-03 | show 페이지 거래이력 탭에 추이 차트 추가 |
| Supplier 납품이력 월별 Chart.js 차트 없음 | FR-05 | show 페이지에 월별 납품 추이 차트 추가 |
| Client 목록 페이지네이션 없음 | FR-02 | Kaminari 또는 수동 페이지네이션 |
| Supplier 목록 통계 카드 없음 | FR-04 | index에 총 거래처 수, 총 공급금액 카드 추가 |
| Supplier 목록 페이지네이션 없음 | FR-04 | 페이지네이션 추가 |
| Project 목록 통계 없음 | FR-07 | 총 예산, 집행금액 통계 카드 추가 |
| Project 상세 오더 탭 없음 | FR-08 | show 페이지에 오더 목록 탭 추가 |

---

## FR-02: Client 목록 고도화

### `app/controllers/clients_controller.rb` 수정

```ruby
def index
  @clients = Client.active.by_name
  @clients = @clients.where("name LIKE ? OR code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
  @clients = @clients.where(country: params[:country]) if params[:country].present?
  @clients = @clients.where(industry: params[:industry]) if params[:industry].present?

  # 정렬 추가
  @clients = case params[:sort]
             when "value" then @clients.sort_by { |c| -c.total_order_value }
             when "orders" then @clients.sort_by { |c| -c.orders.count }
             else @clients  # by_name 기본
             end

  # 페이지네이션 (수동 — Kaminari 미설치)
  @total_count = @clients.size
  @per_page    = 20
  @page        = (params[:page] || 1).to_i
  @clients     = @clients.to_a.slice((@page - 1) * @per_page, @per_page) || []
  @total_pages = (@total_count.to_f / @per_page).ceil

  @total_value = Client.active.sum { |c| c.total_order_value }
end
```

### `app/views/clients/index.html.erb` 추가 사항

**정렬 드롭다운** (검색 폼 내):
```erb
<%= f.select :sort, [["이름순", ""], ["거래금액순", "value"], ["오더수순", "orders"]],
    { selected: params[:sort] }, class: "..." %>
```

**페이지네이션 UI** (테이블 하단):
```erb
<% if @total_pages > 1 %>
  <div class="flex items-center justify-between px-4 py-3 border-t border-gray-100 dark:border-gray-700">
    <span class="text-xs text-gray-500 dark:text-gray-400">
      총 <%= @total_count %>개 중 <%= [(@page-1)*@per_page+1, @total_count].min %>–<%= [@page*@per_page, @total_count].min %>
    </span>
    <div class="flex gap-1">
      <% (1..@total_pages).each do |p| %>
        <%= link_to p, clients_path(params.permit(:q, :country, :industry, :sort).merge(page: p)),
            class: "w-8 h-8 flex items-center justify-center rounded text-xs #{p == @page ? 'bg-primary text-white' : 'text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'}" %>
      <% end %>
    </div>
  </div>
<% end %>
```

---

## FR-03: Client 상세 — 월별 거래이력 차트

### Chart.js 설정 위치
`app/views/clients/show.html.erb` — 거래이력 탭 상단, 필터 폼 위에 삽입

### 데이터 구성 (`clients_controller.rb` `show` 액션 추가)

```ruby
def show
  # ... 기존 코드 ...

  # FR-03: 월별 거래 추이 (최근 12개월)
  @monthly_trend = (11.downto(0)).map do |i|
    m = i.months.ago.to_date.beginning_of_month
    r = m..m.end_of_month
    {
      label:     m.strftime("%y.%m"),
      orders:    @client.orders.where(created_at: r).count,
      value:     (@client.orders.where(created_at: r).sum(:estimated_value).to_f / 1000).round
    }
  end
end
```

### Chart.js 렌더링 (ERB 내 `<script>` 블록)

```erb
<!-- FR-03 월별 거래 추이 차트 -->
<% if @monthly_trend.any? { |m| m[:orders] > 0 } %>
  <div class="mb-4 p-4 bg-gray-50 dark:bg-gray-700/30 rounded-xl">
    <h4 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase mb-3">월별 거래 추이 (최근 12개월)</h4>
    <canvas id="clientTrendChart" height="120"></canvas>
  </div>
  <script>
    (function() {
      const isDark = document.documentElement.classList.contains('dark');
      const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
      const tickColor = isDark ? '#9ca3af' : '#6b7280';
      const labels = <%= raw @monthly_trend.map { |m| m[:label] }.to_json %>;
      const orders = <%= raw @monthly_trend.map { |m| m[:orders] }.to_json %>;
      const values = <%= raw @monthly_trend.map { |m| m[:value] }.to_json %>;

      new Chart(document.getElementById('clientTrendChart'), {
        data: {
          labels,
          datasets: [
            {
              type: 'bar',
              label: '수주액 (K$)',
              data: values,
              backgroundColor: 'rgba(0,161,224,0.15)',
              borderColor: '#00A1E0',
              borderWidth: 1,
              yAxisID: 'y1'
            },
            {
              type: 'line',
              label: '오더 수',
              data: orders,
              borderColor: '#1E3A5F',
              backgroundColor: 'transparent',
              borderWidth: 2,
              pointRadius: 3,
              tension: 0.3,
              yAxisID: 'y'
            }
          ]
        },
        options: {
          responsive: true,
          interaction: { mode: 'index', intersect: false },
          plugins: { legend: { labels: { color: tickColor, font: { size: 11 } } } },
          scales: {
            x: { ticks: { color: tickColor, font: { size: 10 } }, grid: { color: gridColor } },
            y:  { position: 'left',  ticks: { color: tickColor, font: { size: 10 } }, grid: { color: gridColor } },
            y1: { position: 'right', ticks: { color: tickColor, font: { size: 10 } }, grid: { display: false } }
          }
        }
      });
    })();
  </script>
<% end %>
```

### Chart.js CDN 추가
`app/views/layouts/application.html.erb` `<head>` 내 (경영 리포트와 동일):
```html
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
```
※ 이미 추가되어 있으면 생략

---

## FR-04: Supplier 목록 고도화

### `app/controllers/suppliers_controller.rb` 수정

```ruby
def index
  @suppliers = Supplier.by_name
  @suppliers = @suppliers.where("name LIKE ? OR ecount_code LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
  @suppliers = @suppliers.where(country: params[:country]) if params[:country].present?
  @suppliers = @suppliers.where(industry: params[:industry]) if params[:industry].present?

  # 통계 카드
  all_suppliers = Supplier.all
  @total_count       = all_suppliers.count
  @total_supply_value = all_suppliers.sum { |s| s.total_supply_value }
  @active_count      = Supplier.active.count

  # 페이지네이션
  @per_page    = 20
  @page        = (params[:page] || 1).to_i
  @total_pages = (@suppliers.count.to_f / @per_page).ceil
  @suppliers   = @suppliers.offset((@page - 1) * @per_page).limit(@per_page)
end
```

### `app/views/suppliers/index.html.erb` 추가 사항

**통계 카드 3개** (검색 폼 하단, 테이블 위):
```erb
<div class="grid grid-cols-3 gap-4">
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-100 dark:border-gray-700 p-4 shadow-sm">
    <p class="text-xs text-gray-500 dark:text-gray-400">총 거래처</p>
    <p class="text-2xl font-bold text-gray-900 dark:text-white mt-1"><%= @total_count %></p>
  </div>
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-100 dark:border-gray-700 p-4 shadow-sm">
    <p class="text-xs text-gray-500 dark:text-gray-400">총 공급 금액</p>
    <p class="text-xl font-bold text-primary mt-1">$<%= number_with_delimiter(@total_supply_value.round.to_i) %></p>
  </div>
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-100 dark:border-gray-700 p-4 shadow-sm">
    <p class="text-xs text-gray-500 dark:text-gray-400">활성 거래처</p>
    <p class="text-2xl font-bold text-gray-900 dark:text-white mt-1"><%= @active_count %></p>
  </div>
</div>
```

**페이지네이션** (Client 목록과 동일한 패턴)

---

## FR-05: Supplier 상세 — 월별 납품 추이 차트

### 데이터 구성 (`suppliers_controller.rb` `show` 액션 추가)

```ruby
# FR-05: 월별 납품 추이
@monthly_supply = (11.downto(0)).map do |i|
  m = i.months.ago.to_date.beginning_of_month
  r = m..m.end_of_month
  delivered = @supplier.orders.where(status: :delivered).where(updated_at: r)
  {
    label:     m.strftime("%y.%m"),
    orders:    @supplier.orders.where(created_at: r).count,
    delivered: delivered.count,
    value:     (delivered.sum(:estimated_value).to_f / 1000).round
  }
end
```

### Chart.js 렌더링

납품 이력 탭 상단에 삽입. 이중선(수주/납품) + 막대(금액):
```erb
<!-- FR-05 월별 납품 추이 -->
<% if @monthly_supply.any? { |m| m[:orders] > 0 } %>
  <div class="mb-4 p-4 bg-gray-50 dark:bg-gray-700/30 rounded-xl">
    <h4 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase mb-3">월별 납품 추이 (최근 12개월)</h4>
    <canvas id="supplierTrendChart" height="120"></canvas>
  </div>
  <script>
    (function() {
      const isDark = document.documentElement.classList.contains('dark');
      const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
      const tickColor = isDark ? '#9ca3af' : '#6b7280';
      const labels    = <%= raw @monthly_supply.map { |m| m[:label] }.to_json %>;
      const orders    = <%= raw @monthly_supply.map { |m| m[:orders] }.to_json %>;
      const delivered = <%= raw @monthly_supply.map { |m| m[:delivered] }.to_json %>;
      const values    = <%= raw @monthly_supply.map { |m| m[:value] }.to_json %>;

      new Chart(document.getElementById('supplierTrendChart'), {
        data: {
          labels,
          datasets: [
            {
              type: 'bar',
              label: '납품액 (K$)',
              data: values,
              backgroundColor: 'rgba(30,58,95,0.12)',
              borderColor: '#1E3A5F',
              borderWidth: 1,
              yAxisID: 'y1'
            },
            {
              type: 'line',
              label: '수주',
              data: orders,
              borderColor: '#94a3b8',
              backgroundColor: 'transparent',
              borderWidth: 1.5,
              pointRadius: 2,
              borderDash: [4, 3],
              tension: 0.3,
              yAxisID: 'y'
            },
            {
              type: 'line',
              label: '납품 완료',
              data: delivered,
              borderColor: '#1E8E3E',
              backgroundColor: 'transparent',
              borderWidth: 2,
              pointRadius: 3,
              tension: 0.3,
              yAxisID: 'y'
            }
          ]
        },
        options: {
          responsive: true,
          interaction: { mode: 'index', intersect: false },
          plugins: { legend: { labels: { color: tickColor, font: { size: 11 } } } },
          scales: {
            x:  { ticks: { color: tickColor, font: { size: 10 } }, grid: { color: gridColor } },
            y:  { position: 'left',  ticks: { color: tickColor, font: { size: 10 } }, grid: { color: gridColor } },
            y1: { position: 'right', ticks: { color: tickColor, font: { size: 10 } }, grid: { display: false } }
          }
        }
      });
    })();
  </script>
<% end %>
```

---

## FR-07: Project 목록 고도화

### `app/controllers/projects_controller.rb` 수정

```ruby
def index
  @projects = Project.includes(:client, :orders)
  @projects = @projects.where(site_category: params[:category]) if params[:category].present?
  @projects = @projects.where(status: params[:status]) if params[:status].present?
  @projects = @projects.order(:name)

  # 통계 카드
  @total_budget    = @projects.sum(:budget).to_f
  @total_utilized  = @projects.sum { |p| p.budget_utilized }
  @active_count    = Project.active.count
end
```

### `app/views/projects/index.html.erb` 추가 사항

**상태별 필터 탭** (현재 카테고리 필터 옆에):
```erb
<div class="flex gap-2 flex-wrap">
  <%= link_to "전체 상태", projects_path(category: params[:category]),
      class: "px-3 py-1.5 text-xs rounded-full ..." %>
  <% Project::STATUSES.each do |label, val| %>
    <%= link_to label, projects_path(category: params[:category], status: val),
        class: "..." %>
  <% end %>
</div>
```

**통계 카드 3개** (카테고리 필터 하단):
```erb
<div class="grid grid-cols-3 gap-4">
  <div ...><p>총 예산</p><p>$<%= number_with_delimiter(@total_budget.round.to_i) %></p></div>
  <div ...><p>집행금액</p><p>$<%= number_with_delimiter(@total_utilized.round.to_i) %></p></div>
  <div ...><p>진행 현장</p><p><%= @active_count %></p></div>
</div>
```

---

## FR-08: Project 상세 — 오더 탭 추가

### `app/controllers/projects_controller.rb` `show` 수정

```ruby
def show
  @project   = Project.find(params[:id])
  @employees = @project.employees.includes(:employee_assignments)

  # FR-08: 오더 목록
  orders_scope = @project.orders.includes(:client, :supplier, :user)
  orders_scope = case params[:sort]
                 when "value"  then orders_scope.order(estimated_value: :desc)
                 when "recent" then orders_scope.order(created_at: :desc)
                 else               orders_scope.order(due_date: :asc)
                 end
  @orders = orders_scope
  @order_status_counts = @project.orders.group(:status).count
end
```

### `app/views/projects/show.html.erb` 탭 추가

기존 탭에 "오더" 탭 추가:
```erb
<button @click="tab='orders'" :class="...">
  오더 (<%= @orders.count %>)
</button>

<div x-show="tab==='orders'" class="p-4">
  <!-- 상태별 분포 배지 -->
  <!-- 정렬 필터 -->
  <!-- 오더 목록 (Client show와 동일한 카드 패턴) -->
</div>
```

---

## Chart.js CDN 확인 및 추가

`app/views/layouts/application.html.erb` head 섹션에 이미 있는지 확인 후 없으면 추가:

```html
<!-- Chart.js — 경영 리포트 + Client/Supplier 차트 공용 -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
```

---

## 구현 순서

```
1. Chart.js CDN 확인 → 없으면 layouts/application.html.erb 추가
2. clients_controller.rb → show에 @monthly_trend 추가, index에 페이지네이션 추가
3. clients/show.html.erb → 거래이력 탭에 차트 삽입
4. clients/index.html.erb → 정렬 + 페이지네이션 추가
5. suppliers_controller.rb → show에 @monthly_supply 추가, index에 통계+페이지네이션 추가
6. suppliers/show.html.erb → 납품이력 탭에 차트 삽입
7. suppliers/index.html.erb → 통계 카드 + 페이지네이션 추가
8. projects_controller.rb → index 통계, show 오더 탭 추가
9. projects/index.html.erb → 상태 필터 + 통계 카드 추가
10. projects/show.html.erb → 오더 탭 추가
```

---

## 파일 변경 목록

| 파일 | 변경 유형 | 내용 |
|------|---------|------|
| `app/views/layouts/application.html.erb` | 수정 | Chart.js CDN 확인/추가 |
| `app/controllers/clients_controller.rb` | 수정 | 페이지네이션, 정렬, @monthly_trend |
| `app/views/clients/index.html.erb` | 수정 | 정렬 select, 페이지네이션 UI |
| `app/views/clients/show.html.erb` | 수정 | 거래이력 탭 Chart.js 차트 삽입 |
| `app/controllers/suppliers_controller.rb` | 수정 | 통계, 페이지네이션, @monthly_supply |
| `app/views/suppliers/index.html.erb` | 수정 | 통계 카드, 페이지네이션 UI |
| `app/views/suppliers/show.html.erb` | 수정 | 납품이력 탭 Chart.js 차트 삽입 |
| `app/controllers/projects_controller.rb` | 수정 | 통계, 오더 탭 데이터 |
| `app/views/projects/index.html.erb` | 수정 | 상태 필터, 통계 카드 |
| `app/views/projects/show.html.erb` | 수정 | 오더 탭 추가 |

**DB 마이그레이션: 없음**

---

## 비기능 요구사항

- 다크모드: `isDark = document.documentElement.classList.contains('dark')` 분기
- 차트: Chart.js `type: 'bar' + 'line'` 혼합 (경영 리포트와 동일 패턴)
- 페이지네이션: Kaminari 미설치 → 수동 slice/offset 방식
- 다크모드 gridColor: `rgba(255,255,255,0.06)` / tickColor: `#9ca3af`

---

*작성일: 2026-02-28*
*Phase: Design*
