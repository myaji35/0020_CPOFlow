# Feature Design: transaction-tracker

**Feature Name**: 거래내역 추적 강화 (Transaction Tracker)
**Created**: 2026-02-28
**Phase**: Design
**Based On**: `docs/01-plan/features/transaction-tracker.plan.md`

---

## 구현 현황 분석 (실측 AS-IS)

> 코드 탐색 결과 Plan 문서 예상보다 훨씬 많이 구현되어 있음.
> Design은 **미구현 Gap만** 정확히 특정하여 Do 작업 범위를 최소화한다.

### ✅ 이미 구현된 항목

| 기능 | 파일 | 상태 |
|------|------|:----:|
| FR-01: Orders index 검색 + 상태 필터 | `orders/index.html.erb` | ✅ |
| FR-01: 기간 필터 (이번달/3개월/올해) | `orders_controller.rb` | ✅ |
| FR-01: 발주처/거래처/현장/담당자 필터 | `orders_controller.rb` | ✅ |
| FR-02: Client 거래이력 탭 기간 필터 | `clients_controller.rb:37` | ✅ |
| FR-02: Client 거래이력 탭 정렬 (납기/금액/최신) | `clients/show.html.erb:252` | ✅ |
| FR-02: Client 상태별 분포 뱃지 | `clients/show.html.erb:220` | ✅ |
| FR-02: Client 납기준수율 KPI | `clients_controller.rb:56` | ✅ |
| FR-02: Client 월별 거래 추이 Chart.js | `clients/show.html.erb:184` | ✅ |
| FR-03: Supplier 납품이력 탭 기간 필터 | `suppliers_controller.rb:32` | ✅ |
| FR-03: Supplier 납품이력 탭 정렬 | `suppliers_controller.rb:39` | ✅ |
| FR-03: Supplier 상태별 분포 뱃지 | `suppliers/show.html.erb:170` | ✅ |
| FR-03: Supplier 납기준수율 KPI | `suppliers_controller.rb:49` | ✅ |
| FR-03: Supplier 월별 납품 추이 Chart.js | `suppliers/show.html.erb:130` | ✅ |
| FR-04: Project 기간 필터 | `projects_controller.rb:23` | ✅ |
| FR-04: Project 예산 집행 상세 | `projects/show.html.erb:29` | ✅ |
| FR-06: Dashboard 발주처 Top 5 | `dashboard/index.html.erb:431` | ✅ |
| FR-06: Dashboard 거래처 Top 5 | `dashboard/index.html.erb:466` | ✅ |
| Order 모델 scope (active, overdue, urgent, due_soon) | `order.rb:48` | ✅ |

---

### ❌ 미구현 Gap (Do 작업 대상)

#### Gap-01: Client 거래이력 탭 — 상태 필터 없음
- **위치**: `clients/show.html.erb` 거래이력 탭 필터 행
- **현재**: 기간 / 현장 / 정렬만 존재
- **필요**: 상태(status) 필터 추가
- **구현**: `f.select :order_status` + `clients_controller.rb` scope 조건 추가

#### Gap-02: Supplier 납품이력 탭 — 상태 필터 없음
- **위치**: `suppliers/show.html.erb` 납품이력 탭 필터 행
- **현재**: 기간 / 정렬만 존재
- **필요**: 상태 필터 추가
- **구현**: `f.select :order_status` + `suppliers_controller.rb` scope 조건 추가

#### Gap-03: Project 오더 탭 — 상태별 뱃지 카운트 없음
- **위치**: `projects/show.html.erb` 오더 탭
- **현재**: 단순 목록, 상태별 건수 표시 없음
- **필요**: 상태별 오더 수 뱃지 (Inbox N / Delivered N 형태)
- **구현**: `@project_order_status_counts` 인스턴스 변수 추가, 뷰에 뱃지 렌더링

#### Gap-04: Orders index — 납기일 색상 코딩 없음
- **위치**: `orders/index.html.erb` 테이블 납기일 셀
- **현재**: 날짜만 표시 (색상 없음)
- **필요**: D-7 이하 빨강 / D-8~14 주황 / D-15+ 초록
- **구현**: `due_date_color` helper 또는 인라인 조건부 클래스

#### Gap-05: Client/Supplier 거래이력 탭 — CSV 내보내기 없음
- **위치**: 각 show 페이지 거래이력 탭 우측
- **현재**: 내보내기 버튼 없음
- **필요**: CSV 다운로드 링크
- **구현**: `orders.csv` 포맷 응답 + controller `respond_to` 블록

---

## 구현 설계

### Gap-01, 02: 상태 필터 추가

#### Controller (clients_controller.rb, suppliers_controller.rb)
```ruby
# show 액션 orders_scope 부분에 추가
orders_scope = orders_scope.where(status: params[:order_status]) if params[:order_status].present?
```

#### View (필터 form 내 select 추가)
```erb
<%= f.select :order_status,
    [["전체 상태", ""], *Order::STATUS_LABELS.map { |k,v| [v, k] }],
    { selected: params[:order_status] },
    class: "text-xs border ..." %>
```

---

### Gap-03: Project 상태별 뱃지

#### Controller (projects_controller.rb show 액션)
```ruby
@project_order_status_counts = @project.orders.group(:status).count
```

#### View (projects/show.html.erb 오더 탭 상단)
```erb
<div class="flex flex-wrap gap-1.5 mb-4">
  <% Order::STATUS_LABELS.each do |status, label| %>
    <% cnt = @project_order_status_counts[status.to_s] || 0 %>
    <% next if cnt == 0 %>
    <span class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full
                 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-600
                 text-gray-600 dark:text-gray-400">
      <%= label %> <span class="font-bold text-primary"><%= cnt %></span>
    </span>
  <% end %>
</div>
```

---

### Gap-04: 납기일 색상 코딩

#### ApplicationHelper (helpers/application_helper.rb)
```ruby
def due_date_color_class(due_date)
  return "text-gray-400 dark:text-gray-500" if due_date.nil?
  days = (due_date.to_date - Date.today).to_i
  if days < 0         then "text-red-700 dark:text-red-400 font-semibold"   # 초과
  elsif days <= 7     then "text-red-600 dark:text-red-400"                 # D-7
  elsif days <= 14    then "text-orange-500 dark:text-orange-400"           # D-14
  else                     "text-green-600 dark:text-green-400"             # 정상
  end
end
```

#### 적용 위치
- `orders/index.html.erb` 납기일 셀
- `clients/show.html.erb` 거래이력 탭 오더 목록 납기일
- `suppliers/show.html.erb` 납품이력 탭 오더 목록 납기일

---

### Gap-05: CSV 내보내기

#### Route (config/routes.rb) — 별도 route 불필요
Rails `respond_to :html, :csv` 패턴 활용.

#### Controller
```ruby
# clients_controller.rb show 액션
respond_to do |format|
  format.html
  format.csv do
    send_data orders_to_csv(@orders), filename: "#{@client.name}-orders-#{Date.today}.csv"
  end
end

private
def orders_to_csv(orders)
  CSV.generate(headers: true) do |csv|
    csv << ["주문번호", "제목", "상태", "납기일", "금액", "거래처", "현장", "담당자"]
    orders.each do |o|
      csv << [o.id, o.title, Order::STATUS_LABELS[o.status], o.due_date,
              o.total_amount, o.supplier&.name, o.project&.name,
              o.assignees.map(&:display_name).join("|")]
    end
  end
end
```

#### View (거래이력 탭 헤더 우측)
```erb
<%= link_to "CSV", client_path(@client, format: :csv, **request.query_parameters),
    class: "inline-flex items-center gap-1 text-xs text-gray-500 hover:text-primary border
            border-gray-200 dark:border-gray-600 px-2 py-1 rounded-lg" do %>
  <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor"
       stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
    <polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
  CSV
<% end %>
```

---

## 구현 순서 (Do Phase)

| 순서 | 작업 | 파일 | 난이도 |
|:----:|------|------|:------:|
| 1 | `due_date_color_class` helper 추가 | `application_helper.rb` | 낮음 |
| 2 | Orders index 납기일 색상 적용 | `orders/index.html.erb` | 낮음 |
| 3 | Client 상태 필터 (controller + view) | `clients_controller.rb`, `clients/show.html.erb` | 낮음 |
| 4 | Supplier 상태 필터 (controller + view) | `suppliers_controller.rb`, `suppliers/show.html.erb` | 낮음 |
| 5 | Project 상태별 뱃지 (controller + view) | `projects_controller.rb`, `projects/show.html.erb` | 낮음 |
| 6 | Client CSV 내보내기 | `clients_controller.rb`, `clients/show.html.erb` | 중간 |
| 7 | Supplier CSV 내보내기 | `suppliers_controller.rb`, `suppliers/show.html.erb` | 중간 |

**총 예상 파일 수정**: 7개 파일
**신규 파일**: 없음 (모두 기존 파일 수정)

---

## 비고

- Dashboard Top5, Orders 필터, Client/Supplier 월별 차트 등 **핵심 기능은 이미 완성**됨
- 이번 Do 작업은 **UX 마감** 성격 — 색상, 필터 옵션 보완, CSV 내보내기
- `require 'csv'` 가 `config/application.rb`에 이미 선언되어 있는지 확인 필요
- FR-05 (Team 페이지 담당자별 통계)는 다음 사이클로 유지
