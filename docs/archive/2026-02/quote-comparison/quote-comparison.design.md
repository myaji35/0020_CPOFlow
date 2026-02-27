# Design: quote-comparison
> 견적 비교 기능 강화 — 코드 실측 기반 설계

**Feature**: quote-comparison
**Phase**: Design
**Plan 참조**: `docs/01-plan/features/quote-comparison.plan.md`

---

## 코드 실측 결과

### 기존 구현 현황

| 파일 | 상태 | 주요 내용 |
|------|:----:|----------|
| `app/models/order_quote.rb` | ✅ | select!, formatted_price, by_price scope |
| `app/controllers/order_quotes_controller.rb` | ✅ | new/create/destroy/select 4액션 |
| `app/views/order_quotes/` | ❌ | **디렉토리 비어있음 — new.html.erb 없음** |
| `app/views/orders/_sidebar_panel.html.erb` L182~236 | 부분 | 단순 리스트 (비교 테이블 아님) |
| `app/views/orders/pdf/purchase_order.html.erb` L46 | ✅ | `selected_quote` 참조 이미 연동 |

### DB 스키마 (order_quotes)
```
id, order_id, supplier_id, unit_price(decimal), currency(string),
lead_time_days(int), validity_date(date), notes(text),
selected(boolean), submitted_at(datetime), created_at, updated_at
```

### Order 관련 컬럼
```
quantity(int), estimated_value(decimal 12,2), supplier_id(int)
```

### 라우트
```
new_order_order_quote    GET    /orders/:order_id/order_quotes/new
order_order_quotes       POST   /orders/:order_id/order_quotes
select_order_order_quote PATCH  /orders/:order_id/order_quotes/:id/select
order_order_quote        DELETE /orders/:order_id/order_quotes/:id
```

---

## FR별 상세 설계

### FR-01: 견적 추가 폼 (`order_quotes/new` + `_form`)

**문제**: `new_order_order_quote_path` 클릭 시 404 — 뷰 파일 없음

**구현 파일**: `app/views/order_quotes/new.html.erb`

```erb
<%# app/views/order_quotes/new.html.erb %>
<% content_for :page_title, "견적 추가" %>
<div class="max-w-lg mx-auto">
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-6">
    <div class="flex items-center gap-3 mb-5">
      <%= link_to order_path(@order), class: "text-gray-400 hover:text-gray-600" do %>
        <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="15 18 9 12 15 6"/>
        </svg>
      <% end %>
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white">견적 추가</h2>
    </div>
    <p class="text-sm text-gray-500 dark:text-gray-400 mb-5">
      <span class="font-medium text-gray-700 dark:text-gray-300"><%= @order.title %></span>
    </p>
    <%= render "form", order: @order, quote: @quote %>
  </div>
</div>
```

**구현 파일**: `app/views/order_quotes/_form.html.erb`

폼 필드:
- `supplier_id` → select (Supplier.order(:name), prompt: "거래처 선택")
- `unit_price` → number_field (step: 0.01, placeholder: "0.00")
- `currency` → select (%w[USD KRW AED EUR])
- `lead_time_days` → number_field (placeholder: "납기 일수")
- `validity_date` → date_field
- `notes` → text_area (rows: 3)
- 저장/취소 버튼

```erb
<%= form_with model: [@order, @quote], class: "space-y-4" do |f| %>
  <%# supplier_id %>
  <div>
    <%= f.label :supplier_id, "거래처", class: "block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1" %>
    <%= f.collection_select :supplier_id, Supplier.order(:name), :id, :name,
        { prompt: "거래처를 선택하세요" },
        class: "w-full text-sm border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30" %>
  </div>
  <%# unit_price + currency %>
  <div class="flex gap-2">
    <div class="flex-1">
      <%= f.label :unit_price, "단가", class: "block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1" %>
      <%= f.number_field :unit_price, step: 0.01, placeholder: "0.00",
          class: "w-full text-sm border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30" %>
    </div>
    <div class="w-28">
      <%= f.label :currency, "통화", class: "block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1" %>
      <%= f.select :currency, %w[USD KRW AED EUR], { selected: "USD" },
          class: "w-full text-sm border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30" %>
    </div>
  </div>
  <%# lead_time_days %>
  <div>
    <%= f.label :lead_time_days, "납기 일수", class: "block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1" %>
    <%= f.number_field :lead_time_days, placeholder: "예: 14",
        class: "w-full text-sm border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30" %>
  </div>
  <%# validity_date %>
  <div>
    <%= f.label :validity_date, "견적 유효기간", class: "block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1" %>
    <%= f.date_field :validity_date,
        class: "w-full text-sm border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30" %>
  </div>
  <%# notes %>
  <div>
    <%= f.label :notes, "메모", class: "block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1" %>
    <%= f.text_area :notes, rows: 3, placeholder: "특이사항, 조건 등",
        class: "w-full text-sm border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-primary/30 resize-none" %>
  </div>
  <%# actions %>
  <div class="flex justify-end gap-2 pt-2">
    <%= link_to "취소", order_path(@order),
        class: "px-4 py-2 text-sm text-gray-600 dark:text-gray-400 border border-gray-200 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors" %>
    <%= f.submit "견적 저장",
        class: "px-4 py-2 text-sm bg-primary text-white rounded-lg hover:bg-primary/90 transition-colors cursor-pointer" %>
  </div>
<% end %>
```

---

### FR-02: 견적 비교 테이블 (`_sidebar_panel.html.erb` 교체)

**현재**: 단순 세로 리스트 (L194~235)
**변경**: 가로 비교 카드 레이아웃

**구현**: `_sidebar_panel.html.erb` L182~236 섹션 교체

```erb
<%# ── 견적 비교 ── %>
<div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
  <div class="flex items-center justify-between mb-3">
    <h4 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">견적 비교</h4>
    <% if can_update?("orders") %>
      <%= link_to new_order_order_quote_path(order),
          class: "text-xs text-accent hover:underline flex items-center gap-1" do %>
        <svg class="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
        </svg>
        견적 추가
      <% end %>
    <% end %>
  </div>

  <% quotes = order.order_quotes.includes(:supplier).order(unit_price: :asc) %>
  <% min_price = quotes.map(&:unit_price).compact.min %>

  <% if quotes.any? %>
    <div class="space-y-2">
      <% quotes.each do |quote| %>
        <%# 최저가 하이라이트 %>
        <% is_cheapest = quote.unit_price && quote.unit_price == min_price && quotes.count { |q| q.unit_price == min_price } == 1 %>
        <div class="p-2.5 rounded-lg border
          <%= quote.selected? ? 'border-accent bg-accent/5 dark:bg-accent/10' :
              is_cheapest ? 'border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-900/20' :
              'border-gray-100 dark:border-gray-700' %>">
          <%# 헤더: 거래처명 + 배지 %>
          <div class="flex items-center justify-between mb-1.5">
            <p class="text-xs font-semibold text-gray-800 dark:text-white truncate flex items-center gap-1">
              <% if quote.selected? %>
                <span class="text-accent">✓</span>
              <% elsif is_cheapest %>
                <span class="text-green-600 dark:text-green-400 text-xs">최저</span>
              <% end %>
              <%= quote.supplier&.name || "거래처 미지정" %>
            </p>
            <div class="flex items-center gap-1 shrink-0">
              <% if can_update?("orders") && !quote.selected? %>
                <%= button_to select_order_order_quote_path(order, quote), method: :patch,
                    class: "text-xs text-gray-400 hover:text-accent transition-colors bg-transparent border-0 cursor-pointer px-1 py-0",
                    title: "이 견적 선택" do %>선택<% end %>
              <% end %>
              <% if can_update?("orders") %>
                <%= button_to order_order_quote_path(order, quote), method: :delete,
                    data: { turbo_confirm: "이 견적을 삭제하시겠습니까?" },
                    class: "text-gray-300 hover:text-red-400 transition-colors bg-transparent border-0 cursor-pointer p-0.5",
                    title: "삭제" do %>
                  <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                  </svg>
                <% end %>
              <% end %>
            </div>
          </div>
          <%# 가격 + 총액 (FR-03) %>
          <div class="grid grid-cols-2 gap-x-2 text-xs text-gray-500 dark:text-gray-400">
            <div>
              <span class="text-gray-400 dark:text-gray-500">단가</span>
              <p class="font-medium text-gray-700 dark:text-gray-200">
                <%= quote.unit_price ? "#{quote.currency || 'USD'} #{number_with_delimiter(quote.unit_price)}" : "-" %>
              </p>
            </div>
            <div>
              <span class="text-gray-400 dark:text-gray-500">총액</span>
              <p class="font-medium text-gray-700 dark:text-gray-200">
                <% if quote.unit_price && order.quantity.to_i > 0 %>
                  <%= "#{quote.currency || 'USD'} #{number_with_delimiter((quote.unit_price * order.quantity).round(2))}" %>
                <% else %>
                  -
                <% end %>
              </p>
            </div>
            <% if quote.lead_time_days %>
              <div class="mt-1">
                <span class="text-gray-400 dark:text-gray-500">납기</span>
                <p><%= quote.lead_time_days %>일</p>
              </div>
            <% end %>
            <% if quote.validity_date %>
              <div class="mt-1">
                <span class="text-gray-400 dark:text-gray-500">유효기간</span>
                <p><%= quote.validity_date.strftime("%m/%d") %></p>
              </div>
            <% end %>
          </div>
          <% if quote.notes.present? %>
            <p class="text-xs text-gray-400 dark:text-gray-500 mt-1.5 truncate" title="<%= quote.notes %>">
              <%= quote.notes %>
            </p>
          <% end %>
        </div>
      <% end %>
    </div>
  <% else %>
    <p class="text-xs text-gray-400 dark:text-gray-500">아직 등록된 견적이 없습니다.</p>
  <% end %>
</div>
```

---

### FR-03: 수량×단가 총액 (FR-02에 포함)

`_sidebar_panel.html.erb` 내에서 인라인 계산:
```ruby
quote.unit_price * order.quantity  # → 총액
```
- `order.quantity.to_i > 0` 조건 체크
- `number_with_delimiter` 포매팅
- `is_cheapest` 변수로 최저가 하이라이트

**별도 파일 변경 없음** — FR-02 섹션에 통합

---

### FR-04: 선택 → supplier_id 자동 반영

**현재**: `select!` 메서드가 `selected: true`만 업데이트
**변경**: `OrderQuotesController#select` 액션에서 `order.supplier_id` 업데이트 추가

```ruby
# app/controllers/order_quotes_controller.rb — select 액션 수정
def select
  @quote.select!
  # FR-04: 선택된 거래처를 order.supplier_id에 자동 반영
  @quote.order.update(supplier_id: @quote.supplier_id)
  redirect_to @quote.order, notice: "#{@quote.supplier.name} 견적이 선택되었습니다."
end
```

---

## 구현 파일 목록

| 파일 | 변경 유형 | FR |
|------|:--------:|----|
| `app/views/order_quotes/new.html.erb` | 신규 | FR-01 |
| `app/views/order_quotes/_form.html.erb` | 신규 | FR-01 |
| `app/views/orders/_sidebar_panel.html.erb` | 수정 (L182~236) | FR-02, FR-03 |
| `app/controllers/order_quotes_controller.rb` | 수정 (select 액션) | FR-04 |

**총 4개 파일 (신규 2, 수정 2)**

---

## 구현 순서

1. `order_quotes_controller.rb` — select 액션 supplier_id 반영 (FR-04, 5분)
2. `order_quotes/new.html.erb` 신규 생성 (FR-01, 10분)
3. `order_quotes/_form.html.erb` 신규 생성 (FR-01, 15분)
4. `_sidebar_panel.html.erb` 견적 섹션 교체 (FR-02+03, 20분)

---

## 제외 항목 (이미 완성)

- `orders/pdf/purchase_order.html.erb` — `selected_quote` 연동 **이미 완성** → 변경 불필요
- OrderQuote 모델 `select!` 메서드 — 기존 로직 유지
- 라우트 — 모두 존재, 추가 불필요
