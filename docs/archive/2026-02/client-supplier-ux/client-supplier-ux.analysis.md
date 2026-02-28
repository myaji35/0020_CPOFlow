# client-supplier-ux Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit:gap-detector
> **Date**: 2026-02-28
> **Design Doc**: [client-supplier-ux.design.md](../02-design/features/client-supplier-ux.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

client-supplier-ux Design 문서(FR-01/02/04)와 실제 구현 코드 3개 파일 간의 Gap을 검출한다.
보안 항목(WhatsApp gsub, rel="noopener", params[:tab] allowlist)도 별도 검증.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/client-supplier-ux.design.md`
- **Implementation Files**:
  - `app/views/clients/index.html.erb` (FR-01)
  - `app/views/clients/show.html.erb` (FR-02, FR-04)
  - `app/views/suppliers/show.html.erb` (FR-02, FR-04)
- **Analysis Date**: 2026-02-28

---

## 2. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match | 97% | PASS |
| Security Compliance | 100% | PASS |
| Convention Compliance | 100% | PASS |
| **Overall** | **98%** | **PASS** |

---

## 3. FR-01: Client Index Risk Grade Badge

### 3.1 Header Row

| # | Item | Design | Implementation | Status |
|---|------|--------|----------------|--------|
| 1 | "리스크" 헤더 열 존재 | 3.2절 L46 | index.html.erb L58 | PASS |
| 2 | 헤더 순서: 회사명-국가-산업-신용-리스크-오더-거래금액-(액션) | 3.2절 L42~49 | index.html.erb L54~61 | PASS |
| 3 | 헤더 CSS 클래스 일치 | `text-left px-4 py-3 text-xs font-semibold ...` | 동일 | PASS |

### 3.2 Risk Badge Cell

| # | Item | Design | Implementation | Status | Notes |
|---|------|--------|----------------|--------|-------|
| 4 | 리스크 등급 셀 존재 (credit_grade 뒤) | 3.3절 L66~88 | index.html.erb L83~105 | PASS | |
| 5 | overdue 쿼리 로직 | `where("due_date < ? AND status != ?", Date.today, Order.statuses[:delivered])` | 동일 | PASS | |
| 6 | delivered 쿼리 로직 | `where(status: :delivered)` | 동일 | PASS | |
| 7 | rate 계산 | `(delivered.to_f / total) * 100).round(1)` | `(c_delivered.to_f / c_total * 100).round(1)` | PASS | |
| 8 | 등급 판정 로직 A~D | A>=90+overdue0, B>=75\|\|overdue<=1, C>=60\|\|overdue<=3, else D | 동일 | PASS | |
| 9 | 변수명 | `overdue_cnt`, `rate_proxy`, `risk` | `c_overdue`, `c_rate`, `risk_grade` | CHANGED | 로직 동일, 변수명 prefix `c_` 사용 -- 스코프 구분 개선 |
| 10 | A 등급 색상 | `bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-400` | 동일 | PASS | |
| 11 | B 등급 색상 | `bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400` | 동일 | PASS | |
| 12 | C 등급 색상 | `bg-yellow-50 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400` | 동일 | PASS | |
| 13 | D 등급 색상 | `bg-red-50 text-red-700 dark:bg-red-900/30 dark:text-red-400` | 동일 | PASS | |
| 14 | nil 시 대시(-) 표시 | `<span class="text-xs text-gray-300 ...">-</span>` | 동일 | PASS | |
| 15 | 배지 스타일 | `inline-flex px-2 py-0.5 text-xs font-bold rounded-full` | 동일 | PASS | |
| 16 | 배지 텍스트 | `<%= risk %>` | `<%= risk_grade %>` | CHANGED | 변수명만 다름, 출력 동일 |
| 17 | colspan (빈 상태 행) | Design 미명세 | `colspan="8"` (8열에 맞춤) | PASS | 열 추가에 맞춰 업데이트됨 |

**FR-01 소계**: 17항목 중 **15 PASS + 2 CHANGED + 0 FAIL** (100%)

---

## 4. FR-02: Contact Person Icon Buttons

### 4.1 Client Show (clients/show.html.erb)

| # | Item | Design | Implementation | Status |
|---|------|--------|----------------|--------|
| 18 | wrapper div gap | `gap-1.5 mt-1.5` | `gap-1.5 mt-1.5` (L119) | PASS |
| 19 | Email icon button (mailto:) | 4.1절 L120~126 | L121~127 | PASS |
| 20 | Email button 크기/스타일 | `w-7 h-7 rounded-full border ...` | 동일 | PASS |
| 21 | Email SVG (envelope) | 4.1절 L122~125 | L123~126 | PASS |
| 22 | Phone icon button (tel:) | 4.1절 L128~134 | L129~135 | PASS |
| 23 | Phone hover 색상 | `hover:text-green-600 hover:border-green-400` | 동일 | PASS |
| 24 | Phone SVG (telephone) | 4.1절 L131~132 | L132~133 | PASS |
| 25 | WhatsApp icon button (wa.me/) | 4.1절 L136~143 | L137~144 | PASS |
| 26 | WhatsApp hover 색상 | `hover:text-green-500 hover:border-green-400` | 동일 | PASS |
| 27 | WhatsApp SVG (message-circle) | 4.1절 L139~141 | L140~142 | PASS |
| 28 | title tooltip (email) | `title="<%= cp.email %>"` | 동일 | PASS |
| 29 | title tooltip (phone) | `title="<%= cp.phone %>"` | 동일 | PASS |
| 30 | title tooltip (WhatsApp) | `title="WhatsApp: <%= cp.whatsapp %>"` | 동일 | PASS |

### 4.2 Supplier Show (suppliers/show.html.erb)

| # | Item | Design | Implementation | Status |
|---|------|--------|----------------|--------|
| 31 | wrapper div gap | `gap-1.5 mt-1.5` | `gap-1.5 mt-1.5` (L98) | PASS |
| 32 | Email icon button (mailto:) | Client와 동일 패턴 | L100~106 | PASS |
| 33 | Phone icon button (tel:) | Client와 동일 패턴 | L108~114 | PASS |
| 34 | WhatsApp icon button (wa.me/) | Client와 동일 패턴 | L116~123 | PASS |
| 35 | SVG 코드 Client Show와 동일 | Design 명세 | 라인 단위 동일 | PASS |
| 36 | Avatar 배경색 purple 계열 유지 | 4.2절 주석 | `bg-purple-100 dark:bg-purple-900/30` (L94) | PASS |

**FR-02 소계**: 19항목 중 **19 PASS + 0 CHANGED + 0 FAIL** (100%)

---

## 5. FR-04: Tab URL Deep Link

### 5.1 Client Show

| # | Item | Design | Implementation | Status | Notes |
|---|------|--------|----------------|--------|-------|
| 37 | params[:tab] allowlist 적용 | `params[:tab].presence&.in?(%w[contacts projects orders])` | `params[:tab].presence&.then { \|t\| %w[contacts projects orders].include?(t) ? t : 'contacts' } \|\| 'contacts'` | CHANGED | 동일 결과, 다른 Ruby 구문. `&.in?`은 nil 반환 후 삼항 필요 vs `&.then`은 블록 내에서 완결 |
| 38 | allowlist 값 3종 | `contacts`, `projects`, `orders` | 동일 | PASS | |
| 39 | 기본값 contacts | `'contacts'` | `'contacts'` | PASS | |

### 5.2 Supplier Show

| # | Item | Design | Implementation | Status | Notes |
|---|------|--------|----------------|--------|-------|
| 40 | params[:tab] allowlist 적용 | `params[:tab].presence&.in?(%w[contacts products orders])` | `params[:tab].presence&.then { \|t\| %w[contacts products orders].include?(t) ? t : 'contacts' } \|\| 'contacts'` | CHANGED | Client Show와 동일 패턴 차이 |
| 41 | allowlist 값 3종 | `contacts`, `products`, `orders` | 동일 | PASS | |
| 42 | 기본값 contacts | `'contacts'` | `'contacts'` | PASS | |

**FR-04 소계**: 6항목 중 **4 PASS + 2 CHANGED + 0 FAIL** (100%)

---

## 6. Security Compliance

| # | Item | Design (Section 8) | Client Show | Supplier Show | Status |
|---|------|---------------------|-------------|---------------|--------|
| 43 | WhatsApp URL gsub(/\D/,'') | 8절 명세 | L138: `cp.whatsapp.gsub(/\D/, '')` | L117: `cp.whatsapp.gsub(/\D/, '')` | PASS |
| 44 | target="_blank" + rel="noopener" | 8절 명세 | L138: `target="_blank" rel="noopener"` | L117: `target="_blank" rel="noopener"` | PASS |
| 45 | params[:tab] allowlist 검증 | 8절 명세 (XSS 방지) | L77: 3종 allowlist | L70: 3종 allowlist | PASS |

**Security 소계**: 3항목 중 **3 PASS + 0 FAIL** (100%)

---

## 7. Match Rate Summary

```
+-----------------------------------------------+
|  Overall Match Rate: 98%                       |
+-----------------------------------------------+
|  PASS:      41 items (91%)                     |
|  CHANGED:    4 items ( 9%)                     |
|  FAIL:       0 items ( 0%)                     |
|  ADDED:      0 items ( 0%)                     |
+-----------------------------------------------+
|  Total:     45 items                           |
+-----------------------------------------------+
```

### CHANGED Items Detail

| # | GAP ID | File | Design | Implementation | Impact |
|---|--------|------|--------|----------------|--------|
| 9 | GAP-01 | clients/index.html.erb L84~94 | 변수명 `overdue_cnt`, `rate_proxy`, `risk` | 변수명 `c_overdue`, `c_rate`, `risk_grade` | None -- `c_` prefix로 스코프 구분 개선 |
| 16 | GAP-02 | clients/index.html.erb L101 | `<%= risk %>` | `<%= risk_grade %>` | None -- GAP-01 변수명 연동 |
| 37 | GAP-03 | clients/show.html.erb L77 | `&.in?(%w[...]) ? params[:tab] : 'contacts'` | `&.then { \|t\| %w[...].include?(t) ? t : 'contacts' } \|\| 'contacts'` | None -- `&.then` 블록이 nil safe 더 명확 |
| 40 | GAP-04 | suppliers/show.html.erb L70 | `&.in?(%w[...]) ? params[:tab] : 'contacts'` | `&.then { \|t\| %w[...].include?(t) ? t : 'contacts' } \|\| 'contacts'` | None -- GAP-03과 동일 패턴 |

---

## 8. Completion Criteria Verification

| # | Plan Criteria | Design | Implementation | Status |
|---|--------------|--------|----------------|--------|
| CC-01 | Client Index 리스크 등급 배지 | 3.2~3.3절 | index.html.erb L58, L83~105 | PASS |
| CC-02 | Client Show 담당자 아이콘 버튼 | 4.1절 | show.html.erb L119~145 | PASS |
| CC-03 | Supplier Show 담당자 아이콘 버튼 | 4.2절 | show.html.erb L98~124 | PASS |
| CC-04 | Supplier Show KPI 성과등급 | 이미 구현됨 | show.html.erb L59~66 | PASS (기존) |
| CC-05 | Supplier Show 리드타임 표시 | 이미 구현됨 | show.html.erb L21 | PASS (기존) |
| CC-06 | ?tab=orders URL 직링크 | 5.1~5.2절 | client L77, supplier L70 | PASS |
| CC-07 | Gap Analysis >= 90% | 목표 | 98% 달성 | PASS |

**Completion Criteria**: 7/7 PASS

---

## 9. Recommended Actions

### 즉시 조치 필요 사항

없음. FAIL 항목 0건.

### 문서 업데이트 권장

| # | Item | Description |
|---|------|-------------|
| 1 | Design 5.1~5.2절 | `&.in?` 구문을 `&.then` 구문으로 업데이트하여 구현과 일치시킴 (선택) |
| 2 | Design 3.3절 변수명 | `c_` prefix 변수명으로 업데이트하여 구현과 일치시킴 (선택) |

> 4건의 CHANGED 모두 기능적 영향 없음 -- 문서 업데이트는 선택 사항.

---

## 10. View-Layer Concerns

| File | Line | Issue | Severity |
|------|------|-------|----------|
| clients/index.html.erb | L85~88 | `client.orders.count`, `client.orders.where(...)` 뷰에서 직접 쿼리 (N+1) | Low -- Design 자체가 이 패턴, 페이지당 20건 제한으로 MVP 허용 |

> Design 3.3절 주석에서 "현재 페이지당 20건 제한이므로 최대 40 쿼리 -- MVP 수준에서 허용" 명시됨.

---

## 11. Next Steps

- [x] Gap Analysis 수행 (98% -- 목표 90% 초과)
- [ ] Completion Report 생성 (`/pdca report client-supplier-ux`)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial gap analysis | bkit:gap-detector |
