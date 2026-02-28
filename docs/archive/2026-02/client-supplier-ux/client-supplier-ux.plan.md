# client-supplier-ux Plan

## 1. Feature Overview

**Feature Name**: client-supplier-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Medium (4 files)

### 1.1 Summary

발주처(Client) / 거래처(Supplier) 관리 페이지 UX 강화 —
(1) Index 페이지: 리스크 등급 배지 + 활성 오더 인라인 바 + Quick Action 드롭다운,
(2) Show 페이지: "최근 발주" 사이드 패널 + 담당자 카드 클릭 시 mailto/WhatsApp 원터치 액션,
(3) Supplier Show: 납품 성과 등급 배지 + 리드타임 표시 + 납품 이력 필터 개선.

### 1.2 Current State (실측)

**`app/controllers/clients_controller.rb`** (109줄):
- index: 검색/필터/정렬/페이지네이션, `total_order_value` 루비 루프 (N+1 위험)
- show: 거래이력 기간·프로젝트·상태 필터 + CSV 다운로드 + monthly_trend 12개월
- 리스크 등급 계산: `calculate_client_risk` (A~D)

**`app/controllers/suppliers_controller.rb`** (102줄):
- index: 검색/필터/페이지네이션, 통계 카드 (total/active)
- show: 납품이력 기간·상태 필터 + CSV + monthly_supply 12개월
- 성과 등급 계산: `calculate_supplier_performance` (A~D)

**`app/views/clients/index.html.erb`** (122줄):
- 테이블 형태 — 회사명/국가/산업/등급/오더건수/거래금액/상세 링크
- 리스크 등급 표시 없음 (index 레벨)
- 활성 오더 진행도 바 없음

**`app/views/clients/show.html.erb`** (303줄):
- KPI 5카드 (총오더/거래금액/활성/납기준수율/리스크)
- Alpine.js 탭 (담당자/프로젝트/거래이력)
- 거래이력 탭: 차트 + 상태분포 + 필터 + 목록 — 있음
- 문제: 담당자 연락 버튼이 email/phone 텍스트만, 클릭 즉시 연락 불가
- 문제: 거래이력 탭 정렬이 `tab=orders` hidden field 방식이어서 첫 로드 시 contacts 탭이 기본

**`app/views/suppliers/index.html.erb`** (120줄):
- 테이블 — 거래처명/국가/산업/활성여부/오더건수/공급금액/상세
- 성과 등급 표시 없음
- 리드타임 없음

**`app/views/suppliers/show.html.erb`** (275줄):
- KPI 3카드 (총오더/공급금액/납기준수율)
- Alpine.js 탭 (담당자/취급품목/납품이력)
- 취급품목 탭 존재하나 UI 단순
- 성과 등급(A~D) KPI 카드 없음

**문제점**:
1. **Index 리스크/성과 등급 부재**: 목록에서 등급을 바로 볼 수 없어 상세 페이지 진입 필요
2. **담당자 원터치 연락 없음**: email/phone 텍스트 표시만, 버튼 클릭으로 즉시 mailto/tel 실행 불가
3. **Supplier KPI 부족**: 성과 등급 카드 없음, 리드타임 표시 없음
4. **거래이력 탭 URL 의존**: `?tab=orders` 파라미터로 직접 링크 시 orders 탭이 자동 활성화 안 됨

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **Client Index 리스크 배지**: 테이블에 리스크 등급(A~D) 컬러 배지 추가. 현재 credit_grade 배지와 구분하여 `calculate_client_risk` 결과를 inline으로 표시 |
| FR-02 | **담당자 원터치 연락**: Show 담당자 탭의 email/phone/WhatsApp을 아이콘 버튼으로 교체 (mailto:, tel:, https://wa.me 링크) |
| FR-03 | **Supplier Show KPI 강화**: 성과 등급 카드 추가 (총오더/공급금액/납기준수율/성과등급 4카드로 확장) + 리드타임 표시 |
| FR-04 | **거래이력 탭 URL 직링크**: `?tab=orders` 파라미터 수신 시 Alpine.js tab 초기값을 `orders`로 설정 |

### Out of Scope
- Client/Supplier CRUD 폼 변경
- 새 DB 마이그레이션
- 실시간 WebSocket 갱신

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/views/clients/index.html.erb` | FR-01: 테이블에 리스크 등급 배지 열 추가 |
| `app/views/clients/show.html.erb` | FR-02: 담당자 연락 아이콘 버튼 + FR-04: URL 탭 직링크 |
| `app/views/suppliers/show.html.erb` | FR-03: KPI 카드 확장 (성과등급 + 리드타임) + FR-04: URL 탭 직링크 |

### 3.2 FR-01: Client Index 리스크 배지

컨트롤러는 이미 `calculate_client_risk`가 있으나 index에는 미노출.
index에서는 `@clients` 배열 순회 시 리스크를 계산하면 N+1 발생 가능.
→ 뷰에서 `active_orders_count`와 `on_time_rate` 근사치로 간단 계산:

```erb
<%# 활성 오더 비율로 리스크 간이 표시 %>
<% overdue_proxy = client.orders.where("due_date < ? AND status != ?", Date.today, Order.statuses[:delivered]).count rescue 0 %>
<% rate_proxy = client.orders.count > 0 ? ((client.orders.where(status: :delivered).count.to_f / client.orders.count) * 100).round : nil %>
```

단, N+1 방지를 위해 `includes(:orders)` 추가는 컨트롤러에서 처리.

### 3.3 FR-02: 담당자 원터치 연락 버튼

```erb
<%# 변경 전 — 텍스트 링크 %>
<a href="mailto:<%= cp.email %>"><%= cp.email %></a>

<%# 변경 후 — 아이콘 버튼 %>
<% if cp.email.present? %>
  <a href="mailto:<%= cp.email %>" title="<%= cp.email %>"
     class="inline-flex items-center justify-center w-7 h-7 rounded-full border border-gray-200 dark:border-gray-600 text-gray-500 hover:text-primary hover:border-primary transition-colors">
    <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/>
      <polyline points="22,6 12,13 2,6"/>
    </svg>
  </a>
<% end %>
<% if cp.phone.present? %>
  <a href="tel:<%= cp.phone %>" title="<%= cp.phone %>" class="...">
    <svg ...>phone icon</svg>
  </a>
<% end %>
<% if cp.whatsapp.present? %>
  <a href="https://wa.me/<%= cp.whatsapp.gsub(/\D/, '') %>" target="_blank" title="WhatsApp: <%= cp.whatsapp %>" class="... text-green-600">
    WhatsApp SVG
  </a>
<% end %>
```

Supplier show에도 동일 패턴 적용.

### 3.4 FR-03: Supplier Show KPI 카드 확장

현재 3카드 → 4카드로 확장:

```erb
<!-- 기존 3카드 -->
총오더 | 공급금액 | 납기준수율

<!-- 변경 후 4카드 -->
총오더 | 공급금액 | 납기준수율 | 성과등급
```

리드타임도 헤더 메타 정보에 추가:
```erb
<% if @supplier.lead_time_days.present? %>
  <span class="text-xs">리드타임 <strong><%= @supplier.lead_time_days %>일</strong></span>
<% end %>
```

### 3.5 FR-04: 거래이력 탭 URL 직링크

Alpine.js `x-data`에서 초기 탭 값을 URL 파라미터로 설정:

```erb
<%# 변경 전 %>
<div x-data="{ tab: 'contacts' }">

<%# 변경 후 %>
<div x-data="{ tab: '<%= params[:tab].presence || 'contacts' %>' }">
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | Client Index 테이블에 리스크 등급 배지 표시 |
| 2 | Client/Supplier Show 담당자 탭 — email/phone/WhatsApp 아이콘 버튼 클릭 시 즉시 실행 |
| 3 | Supplier Show KPI 카드 4개 (성과등급 추가) |
| 4 | Supplier Show 헤더에 리드타임 표시 |
| 5 | `?tab=orders` URL로 직접 접근 시 거래이력 탭 자동 활성화 |
| 6 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `calculate_client_risk`, `calculate_supplier_performance` — 기존 컨트롤러 private 메서드 존재
- `ContactPerson#email`, `#phone`, `#whatsapp` — 기존 필드 존재
- `Supplier#lead_time_days` — 기존 필드 존재
- Alpine.js (`x-data`, `x-show`) — layout에 기존 로드

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
