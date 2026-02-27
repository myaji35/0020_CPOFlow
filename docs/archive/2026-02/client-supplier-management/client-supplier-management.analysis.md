# client-supplier-management Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Feature**: client-supplier-management (Phase 4)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Phase 4 Client/Supplier Management 설계 문서의 GAP 항목 7개가 실제 코드에 구현되었는지 검증한다.

### 1.2 Analysis Scope

- **Design Document**: GAP 항목 7개 (FR-02 ~ FR-08)
- **Implementation Path**: `app/controllers/`, `app/views/clients/`, `app/views/suppliers/`, `app/views/projects/`
- **Analysis Date**: 2026-02-28

---

## 2. GAP Analysis (Design vs Implementation)

### 2.1 Overall Match Rate

```
+-------------------------------------------------+
|  Overall Match Rate: 100% (7/7 PASS)            |
+-------------------------------------------------+
|  PASS:    7 items                                |
|  PARTIAL: 0 items                                |
|  FAIL:    0 items                                |
+-------------------------------------------------+
```

### 2.2 Detailed GAP Item Analysis

#### GAP-1: Client 거래이력 월별 Chart.js 차트 (FR-03)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | clients/show.html.erb 거래이력 탭에 @monthly_trend 기반 bar+line 혼합 차트 |
| **Controller** | `clients_controller.rb:59-68` -- `@monthly_trend` 최근 12개월 월별 데이터 생성 (label, orders, value) |
| **View** | `clients/show.html.erb:183-217` -- Chart.js CDN 로드, bar(오더 건수) + line(거래금액 천$) 혼합 차트 |

**구현 상세:**
- Chart.js 4.4.0 CDN via `content_for :head` (show.html.erb:3)
- `@monthly_trend`: 12개월 역순 순회, month별 orders count + estimated_value 합계 (천$ 단위)
- Chart config: dual Y-axis (y: 건수, y2: 천$), bar + line type, dark mode 대응 (gridColor, textColor)
- 데이터가 없는 경우(`@monthly_trend.any? { |m| m[:orders] > 0 }`) 차트 미표시

---

#### GAP-2: Supplier 납품이력 월별 Chart.js 차트 (FR-05)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | suppliers/show.html.erb 납품이력 탭에 @monthly_supply 기반 bar+bar+line 혼합 차트 |
| **Controller** | `suppliers_controller.rb:52-63` -- `@monthly_supply` 최근 12개월 월별 데이터 생성 (label, orders, delivered, value) |
| **View** | `suppliers/show.html.erb:130-166` -- Chart.js CDN 로드, bar(발주) + bar(납품) + line(납품금액 천$) 혼합 차트 |

**구현 상세:**
- Chart.js 4.4.0 CDN via `content_for :head` (show.html.erb:3)
- `@monthly_supply`: 12개월 역순 순회, 4개 필드 (label, orders, delivered, value)
- Chart config: 3 datasets -- bar(발주, 파랑), bar(납품, 초록), line(납품금액, navy)
- dual Y-axis (y: 건수 stepSize:1, y2: 천$)
- 데이터 존재 조건: `@monthly_supply.any? { |m| m[:orders] > 0 || m[:delivered] > 0 }`

---

#### GAP-3: Client 목록 페이지네이션 (FR-02)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | clients/index.html.erb 페이지네이션 UI + clients_controller.rb 수동 페이지네이션 |
| **Controller** | `clients_controller.rb:22-28` -- 수동 페이지네이션 (@per_page=20, @page, @total_count, @total_pages) |
| **View** | `clients/index.html.erb:95-121` -- 이전/다음 버튼 + 페이지 번호 (현재 페이지 +/-2 범위) |

**구현 상세:**
- Controller: `all.slice((@page - 1) * @per_page, @per_page)` 배열 슬라이싱 방식
- 이유: 정렬이 Ruby 메모리 내(to_a -> sort_by)에서 수행되므로 SQL LIMIT/OFFSET 사용 불가
- View: `params.permit(:q, :country, :industry, :sort)` 기존 필터 파라미터 유지
- 페이지 범위: `[@page-2, 1].max..[@page+2, @total_pages].min`
- "총 N개 중 M-N개 표시" 텍스트 포함

---

#### GAP-4: Client 목록 정렬 (FR-02)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | clients/index.html.erb 정렬 select dropdown 추가 |
| **Controller** | `clients_controller.rb:13-18` -- params[:sort] 기반 정렬 (value, orders, default: name) |
| **View** | `clients/index.html.erb:27-28` -- sort select dropdown (이름순/거래금액순/오더건수순) |

**구현 상세:**
- Controller 정렬 로직: `case params[:sort]` -- "value" -> total_order_value DESC, "orders" -> orders.count DESC, else -> 기본 이름순(by_name scope)
- View: `f.select :sort, options_for_select([["이름순",""], ["거래금액순","value"], ["오더건수순","orders"]])`
- 정렬은 메모리 내(`all.sort_by`) 수행 -- 데이터 규모가 작은 MVP에 적합

---

#### GAP-5: Supplier 목록 통계 카드 (FR-04)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | suppliers/index.html.erb 통계 카드 3개 (@total_count, @total_supply_value, @active_count) |
| **Controller** | `suppliers_controller.rb:11-15` -- 3개 인스턴스 변수 계산 |
| **View** | `suppliers/index.html.erb:30-45` -- grid-cols-3 통계 카드 UI |

**구현 상세:**
- `@total_count = all_suppliers.size` (전체 거래처 수)
- `@total_supply_value = all_suppliers.sum(&:total_supply_value)` (총 공급금액)
- `@active_count = Supplier.active.count` (활성 거래처 수)
- View: 3열 그리드, 각 카드에 라벨 + 수치 + 서브텍스트

---

#### GAP-6: Supplier 목록 페이지네이션 (FR-04)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | suppliers/index.html.erb 페이지네이션 UI |
| **Controller** | `suppliers_controller.rb:17-23` -- 수동 페이지네이션 (@per_page=20, SQL offset/limit) |
| **View** | `suppliers/index.html.erb:93-119` -- 이전/다음 버튼 + 페이지 번호 |

**구현 상세:**
- Controller: Client와 달리 SQL `.offset().limit()` 방식 사용 (메모리 정렬 불필요)
- `@filtered_count = @suppliers.count` (필터 적용 후 총 수)
- View: `params.permit(:q, :country, :industry)` 기존 필터 파라미터 유지
- Client 페이지네이션과 동일한 UI 패턴

---

#### GAP-7: Project 목록 통계 카드 + 상태 필터 (FR-07)

| Category | Detail |
|----------|--------|
| **Status** | PASS |
| **Design** | projects/index.html.erb 통계 카드 3개 + 상태 필터 탭 |
| **Controller** | `projects_controller.rb:8-9,13-17` -- 상태 필터(params[:status]) + 통계 변수 3개 |
| **View** | `projects/index.html.erb:16-52` -- 통계 카드 3개 + 카테고리 필터 + 상태 필터 탭 |

**구현 상세:**

*통계 카드:*
- `@total_budget` (총 예산)
- `@total_utilized` (총 집행금액, 예산 대비 % 표시)
- `@active_count` (진행 현장 수, "전체 N개 중" 서브텍스트)

*상태 필터:*
- Controller: `@projects = @projects.where(status: params[:status]) if params[:status].present?`
- View: 4개 상태 탭 (진행중/계획/완료/중단) + "전체 상태" 버튼
- 카테고리 필터(원전/수력/터널/GTX/일반)와 상태 필터 독립 동작 (둘 다 URL 파라미터 유지)

---

### 2.3 추가 확인: FR-08 Project Show 오더 탭

| Category | Detail |
|----------|--------|
| **Status** | PASS (추가 확인) |
| **Controller** | `projects_controller.rb:20-30` -- 오더 스코프, 기간 필터, 상태별 그룹 카운트 |
| **View** | `projects/show.html.erb:56-150` -- "관련 오더" 탭 + 투입 인력 탭 |

**구현 상세:**
- 2개 탭: "관련 오더" (default) + "투입 인력"
- 오더 탭: 상태별 뱃지 바 + 기간 필터 (전체/이번달/3개월/올해) + 오더 목록 (납기일 색상 코딩)
- 투입 인력 탭: `@employee_assignments` -- 현장 배정 인력 목록

---

## 3. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match | 100% | PASS |
| Architecture Compliance | N/A | -- |
| Convention Compliance | N/A | -- |
| **Overall** | **100%** | **PASS** |

---

## 4. Code Quality Notes

### 4.1 Client Controller 정렬 방식

`clients_controller.rb:13-18`에서 `to_a` 후 메모리 내 정렬을 수행하고 있다. 이는 `total_order_value` 와 `orders.count`가 computed 값이라 SQL 정렬이 어렵기 때문이며, 데이터 규모가 작은 현재 MVP 단계에서는 적절하다. 데이터가 커지면 counter_cache 또는 DB 집계 컬럼 도입을 권장한다.

### 4.2 Supplier Controller 페이지네이션 방식 차이

Client는 배열 슬라이싱(`all.slice`), Supplier는 SQL offset/limit 방식이다. 이유는 Client에서 computed 값 정렬이 필요하기 때문이며, 논리적으로 타당하다.

### 4.3 Chart.js CDN 로딩

두 show 뷰 모두 `content_for :head`로 Chart.js CDN을 로드한다. layout에서 `yield :head`가 선언되어 있어야 정상 동작한다.

---

## 5. Recommended Actions

### 5.1 현재 상태

모든 GAP 항목이 설계 의도에 맞게 구현되었으므로 즉시 조치가 필요한 항목은 없다.

### 5.2 향후 개선 (Backlog)

| Priority | Item | Description |
|----------|------|-------------|
| Low | Client 정렬 최적화 | counter_cache 도입으로 SQL 레벨 정렬 전환 |
| Low | Project 페이지네이션 | 현재 Project 목록에는 페이지네이션이 없음 (데이터 증가시 필요) |
| Low | Chart.js 번들 통합 | 여러 페이지에서 사용시 layout 레벨 조건부 로딩 고려 |

---

## 6. Analysis Summary

| GAP # | FR | Item | Implementation Files | Status |
|:-----:|:--:|------|---------------------|:------:|
| 1 | FR-03 | Client 월별 Chart.js 차트 | clients_controller.rb:59-68, clients/show.html.erb:183-217 | PASS |
| 2 | FR-05 | Supplier 월별 Chart.js 차트 | suppliers_controller.rb:52-63, suppliers/show.html.erb:130-166 | PASS |
| 3 | FR-02 | Client 목록 페이지네이션 | clients_controller.rb:22-28, clients/index.html.erb:95-121 | PASS |
| 4 | FR-02 | Client 목록 정렬 | clients_controller.rb:13-18, clients/index.html.erb:27-28 | PASS |
| 5 | FR-04 | Supplier 목록 통계 카드 | suppliers_controller.rb:11-15, suppliers/index.html.erb:30-45 | PASS |
| 6 | FR-04 | Supplier 목록 페이지네이션 | suppliers_controller.rb:17-23, suppliers/index.html.erb:93-119 | PASS |
| 7 | FR-07 | Project 통계 카드 + 상태 필터 | projects_controller.rb:8-17, projects/index.html.erb:16-52 | PASS |

**Match Rate: 100% (7/7 PASS)**

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial gap analysis - 7 GAP items all PASS | bkit-gap-detector |
