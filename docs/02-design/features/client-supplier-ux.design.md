# client-supplier-ux Design

## 1. Overview

**Feature**: client-supplier-ux
**Phase**: Design
**Created**: 2026-02-28
**Plan Reference**: `docs/01-plan/features/client-supplier-ux.plan.md`

발주처(Client) / 거래처(Supplier) 관리 페이지 UX 4가지 개선.
컨트롤러 변경 없음 — 뷰 3개 파일만 수정.

---

## 2. Files to Modify

| File | Lines (현재) | 변경 내용 |
|------|:-----------:|-----------|
| `app/views/clients/index.html.erb` | 122 | FR-01: 테이블 헤더 + 각 행에 리스크 등급 배지 열 추가 |
| `app/views/clients/show.html.erb` | 303 | FR-02: 담당자 연락 아이콘 버튼 + FR-04: 탭 URL 직링크 |
| `app/views/suppliers/show.html.erb` | 275 | FR-02: 담당자 연락 아이콘 버튼 + FR-04: 탭 URL 직링크 |

> Supplier Index는 이미 `credit_grade` 배지가 있고, `performance_grade`는 show에서 계산되므로 Index 수정 제외.

---

## 3. FR-01: Client Index 리스크 등급 배지

### 3.1 현재 코드 위치

`app/views/clients/index.html.erb` — L54~60 테이블 헤더, L76~80 등급 셀

현재 헤더:
```
회사명 | 국가 | 산업 | 등급(credit_grade) | 오더 | 거래금액 | (액션)
```

### 3.2 변경: 헤더에 "리스크" 열 추가

```erb
<%# L54 ~ L61 — 헤더 변경 %>
<th class="text-left px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">회사명</th>
<th class="text-left px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">국가</th>
<th class="text-left px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">산업</th>
<th class="text-left px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">신용</th>
<th class="text-left px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">리스크</th>
<th class="text-right px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">오더</th>
<th class="text-right px-4 py-3 text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">거래금액</th>
<th class="px-4 py-3"></th>
```

### 3.3 변경: 각 행에 리스크 배지 셀 추가

현재 credit_grade 셀 (L76~80) 이후에 리스크 셀 삽입:

```erb
<%# 기존 credit_grade 셀 유지 %>
<td class="px-4 py-3">
  <% if client.credit_grade.present? %>
    <% grade_class = { ... }[client.credit_grade] || "bg-gray-50 ..." %>
    <span class="inline-flex px-2 py-0.5 text-xs font-bold rounded-full <%= grade_class %>"><%= client.credit_grade %>등급</span>
  <% end %>
</td>

<%# 신규: 리스크 등급 배지 셀 %>
<td class="px-4 py-3">
  <%
    overdue_cnt  = client.orders.where("due_date < ? AND status != ?", Date.today, Order.statuses[:delivered]).count
    delivered    = client.orders.where(status: :delivered).count
    total        = client.orders.count
    rate_proxy   = total > 0 ? ((delivered.to_f / total) * 100).round(1) : nil
    risk = if rate_proxy.nil? then nil
           elsif rate_proxy >= 90 && overdue_cnt == 0 then "A"
           elsif rate_proxy >= 75 || overdue_cnt <= 1  then "B"
           elsif rate_proxy >= 60 || overdue_cnt <= 3  then "C"
           else "D"
           end
    risk_cls = { "A" => "bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-400",
                 "B" => "bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400",
                 "C" => "bg-yellow-50 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400",
                 "D" => "bg-red-50 text-red-700 dark:bg-red-900/30 dark:text-red-400" }
  %>
  <% if risk %>
    <span class="inline-flex px-2 py-0.5 text-xs font-bold rounded-full <%= risk_cls[risk] %>"><%= risk %></span>
  <% else %>
    <span class="text-xs text-gray-300 dark:text-gray-600">-</span>
  <% end %>
</td>
```

> N+1 주의: `@clients`가 이미 `.active.by_name` 배열로 로드됨. 각 client당 2 SQL 추가 발생.
> 현재 페이지당 20건 제한이므로 최대 40 쿼리 — MVP 수준에서 허용.
> 추후 개선 시 컨트롤러에서 batch 로드 가능.

---

## 4. FR-02: 담당자 원터치 연락 아이콘 버튼

### 4.1 Client Show — 담당자 탭 (L104~142)

현재 연락처 표시 (L119~129):
```erb
<div class="flex items-center gap-3 mt-1">
  <% if cp.email.present? %>
    <a href="mailto:<%= cp.email %>" class="text-xs text-primary hover:underline"><%= cp.email %></a>
  <% end %>
  <% if cp.phone.present? %>
    <span class="text-xs text-gray-400 dark:text-gray-500"><%= cp.phone %></span>
  <% end %>
  <% if cp.whatsapp.present? %>
    <span class="text-xs text-green-600 dark:text-green-400">WhatsApp: <%= cp.whatsapp %></span>
  <% end %>
</div>
```

변경 후 — 아이콘 버튼 + tooltip:
```erb
<div class="flex items-center gap-1.5 mt-1.5">
  <% if cp.email.present? %>
    <a href="mailto:<%= cp.email %>" title="<%= cp.email %>"
       class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200 dark:border-gray-600 text-gray-400 hover:text-primary hover:border-primary transition-colors">
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/>
        <polyline points="22,6 12,13 2,6"/>
      </svg>
    </a>
  <% end %>
  <% if cp.phone.present? %>
    <a href="tel:<%= cp.phone %>" title="<%= cp.phone %>"
       class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200 dark:border-gray-600 text-gray-400 hover:text-green-600 hover:border-green-400 transition-colors">
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 13 19.79 19.79 0 0 1 1.61 4.37 2 2 0 0 1 3.58 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L7.91 9.91a16 16 0 0 0 6.18 6.18l1.97-1.97a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z"/>
      </svg>
    </a>
  <% end %>
  <% if cp.whatsapp.present? %>
    <a href="https://wa.me/<%= cp.whatsapp.gsub(/\D/, '') %>" target="_blank" rel="noopener" title="WhatsApp: <%= cp.whatsapp %>"
       class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200 dark:border-gray-600 text-gray-400 hover:text-green-500 hover:border-green-400 transition-colors">
      <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>
      </svg>
    </a>
  <% end %>
</div>
```

### 4.2 Supplier Show — 담당자 탭 (L91~110)

현재 연락처 (L98~100):
```erb
<div class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
  <%= cp.email %> <% if cp.phone.present? %> | <%= cp.phone %><% end %>
</div>
```

변경 후 — Client Show와 동일한 아이콘 버튼 패턴 적용 (색상은 purple 계열 유지):
```erb
<div class="flex items-center gap-1.5 mt-1.5">
  <%# 동일한 아이콘 버튼 3종 (email/phone/whatsapp) %>
  <%# hover 색상: email→primary, phone→green-600, whatsapp→green-500 %>
</div>
```

---

## 5. FR-04: 거래이력 탭 URL 직링크

### 5.1 Client Show (L77)

현재:
```erb
<div x-data="{ tab: 'contacts' }" class="bg-white ...">
```

변경 후:
```erb
<div x-data="{ tab: '<%= params[:tab].presence&.in?(%w[contacts projects orders]) ? params[:tab] : 'contacts' %>' }" class="bg-white ...">
```

> XSS 방지: `params[:tab]`을 allowlist(`contacts`, `projects`, `orders`)로 검증 후 적용.

### 5.2 Supplier Show (L70)

현재:
```erb
<div x-data="{ tab: 'contacts' }" class="bg-white ...">
```

변경 후:
```erb
<div x-data="{ tab: '<%= params[:tab].presence&.in?(%w[contacts products orders]) ? params[:tab] : 'contacts' %>' }" class="bg-white ...">
```

> Supplier 탭은 `contacts`, `products`, `orders` 3종.

---

## 6. Implementation Order (Do Phase 순서)

```
Step 1: clients/index.html.erb
  - 테이블 헤더에 "리스크" 열 추가
  - 각 행에 리스크 등급 배지 셀 추가

Step 2: clients/show.html.erb
  - 담당자 탭 연락처 → 아이콘 버튼 교체 (FR-02)
  - x-data 탭 초기값 URL 파라미터 반영 (FR-04)

Step 3: suppliers/show.html.erb
  - 담당자 탭 연락처 → 아이콘 버튼 교체 (FR-02)
  - x-data 탭 초기값 URL 파라미터 반영 (FR-04)
```

---

## 7. Completion Criteria (Plan 대비)

| # | Plan 기준 | Design 반영 여부 |
|---|-----------|:----------------:|
| 1 | Client Index 리스크 등급 배지 | ✅ 3.2~3.3절 |
| 2 | Client Show 담당자 아이콘 버튼 | ✅ 4.1절 |
| 3 | Supplier Show 담당자 아이콘 버튼 | ✅ 4.2절 |
| 4 | Supplier Show KPI 성과등급 | ✅ 이미 구현됨 (show.html.erb L59~66) |
| 5 | Supplier Show 리드타임 표시 | ✅ 이미 구현됨 (show.html.erb L21) |
| 6 | `?tab=orders` URL 직링크 | ✅ 5.1~5.2절 |
| 7 | Gap Analysis >= 90% | 목표 |

> FR-03 (Supplier KPI 강화)와 리드타임 표시는 이미 현재 코드에 구현되어 있음.
> Plan의 FR-03은 "이미 충족" 상태이므로 Design에서는 FR-01/02/04 3가지에 집중.

---

## 8. Security Notes

- `params[:tab]` 직접 삽입 금지 — allowlist 검증 필수 (5.1~5.2절 적용)
- WhatsApp URL: `gsub(/\D/, '')` 로 숫자만 추출하여 XSS 방지
- `target="_blank"` 링크에 `rel="noopener"` 필수 적용

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
