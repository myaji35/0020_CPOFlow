# Feature Plan: ux-enhancement

**Feature Name**: 실무 UX 편의 기능 강화
**Created**: 2026-02-28
**Phase**: Plan

---

## 개요

매일 사용하는 핵심 화면(칸반·오더 목록·오더 상세)의 실무 편의성을 높인다.
이미 기반 인프라(bulk_controller, bulk_select_controller, move_status 액션, 필터 파라미터)가
구축되어 있으므로 **UI 연결·확장**이 중심이다.

---

## AS-IS 현황 (이미 구현됨)

| 항목 | 상태 | 파일 |
|------|:----:|------|
| `Orders::BulkController` — status/priority/assign/export_csv | ✅ | `orders/bulk_controller.rb` |
| `bulk_select_controller.js` — 체크박스 선택·액션바·CSV | ✅ | `javascript/controllers/bulk_select_controller.js` |
| `OrdersController#move_status` — 상태 변경 액션 | ✅ | `orders_controller.rb:84` |
| Orders index 필터 — client/supplier/project/user/period | ✅ | `orders_controller.rb:8-29` |
| Orders index 날짜 범위 — date_from/date_to (created_at 기준) | ✅ | `orders_controller.rb:27-28` |

---

## TO-DO Gap (이번 구현 대상)

### FR-01: 칸반 드래그 → Turbo Stream 즉시 반영

- **현재**: `move_status` 액션이 `redirect_back` → 전체 페이지 새로고침
- **필요**: Turbo Stream 응답으로 해당 카드만 이동 (새로고침 없음)
- **구현**:
  - `move_status` 액션에 `respond_to :html, :turbo_stream` 추가
  - 칸반 뷰: `data-turbo-stream` 또는 `turbo_stream_from` 연결
  - 카드를 다른 컬럼으로 드래그 시 JS → fetch PATCH → turbo stream 응답

### FR-02: 일괄 처리 액션바 UI 완성

- **현재**: `bulk_select_controller.js`가 form submit 방식으로 구현되어 있으나
  orders index 뷰에 **실제 bulk action 폼/버튼 UI가 미흡** (상태변경·담당자배정 UI 누락)
- **필요**: 선택 시 하단 플로팅 액션바에 "상태 변경", "담당자 배정" 드롭다운 추가
- **구현**:
  - `orders/index.html.erb` 액션바 섹션에 status 드롭다운 + user 드롭다운 추가
  - Stimulus `bulkAction` 연결 (이미 `action_type` 파라미터 처리 완비)

### FR-03: 납기일 기준 날짜 범위 필터 추가

- **현재**: `date_from/date_to`가 **`created_at` 기준** 필터만 존재
- **필요**: `due_date` 기준 날짜 범위 필터 (`due_from`, `due_to`)
- **구현**:
  - `orders_controller.rb` index 액션에 `due_from`/`due_to` 필터 추가
  - `orders/index.html.erb` 필터 폼에 납기일 범위 입력 추가

### FR-04: 오더 목록 인라인 빠른 수정 (납기일·상태)

- **현재**: 납기일·상태 수정을 위해 반드시 edit 페이지 또는 드로어를 열어야 함
- **필요**: 오더 목록 행에서 납기일 직접 수정 (date input), 상태 드롭다운 변경
- **구현**:
  - 납기일 셀: `<input type="date">` + `data-action="change->inline-edit#saveDueDate"` Stimulus
  - 상태 셀: `<select>` + `data-action="change->inline-edit#saveStatus"` Stimulus
  - 새 Stimulus 컨트롤러 `inline_edit_controller.js` — fetch PATCH → 반영
  - 백엔드: `OrdersController#quick_update` 액션 추가 (due_date, status만 허용)

---

## 기능 요구사항

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-01 | 칸반 상태 변경 Turbo Stream (새로고침 없음) | HIGH |
| FR-02 | 일괄 처리 액션바 상태·담당자 변경 UI | HIGH |
| FR-03 | 납기일(due_date) 기준 날짜 범위 필터 | MEDIUM |
| FR-04 | 오더 목록 인라인 납기일·상태 빠른 수정 | HIGH |

---

## 기술 결정

| 항목 | 선택 | 이유 |
|------|------|------|
| 칸반 실시간 반영 | Turbo Stream (format: :turbo_stream) | SPA 불필요, Rails 기본 Hotwire 활용 |
| 인라인 수정 | 새 Stimulus 컨트롤러 `inline_edit` | 기존 bulk_select와 책임 분리 |
| 일괄 처리 | 기존 BulkController 재활용 | 이미 완성된 백엔드 그대로 사용 |
| 날짜 필터 | due_from/due_to 파라미터 추가 | created_at 기반과 병렬 운용 |

---

## 범위 (이번 사이클)

**포함**
- FR-01 ~ FR-04 (4개 항목)
- 수정/신규 파일: 최대 6개

**제외 (다음 사이클)**
- 저장된 필터 프리셋 (북마크)
- 칸반 SortableJS 완전 드래그 (마우스 드래그앤드롭)
- 오더 코멘트 인라인 편집

---

## 연관 파일

- `app/controllers/orders_controller.rb` — FR-03 due_from/due_to, FR-04 quick_update 추가
- `app/views/kanban/index.html.erb` — FR-01 Turbo Stream 연결
- `app/views/orders/index.html.erb` — FR-02 액션바 UI, FR-03 필터, FR-04 인라인 수정
- `app/javascript/controllers/inline_edit_controller.js` — FR-04 신규
- `app/views/orders/move_status.turbo_stream.erb` — FR-01 신규 Turbo Stream 템플릿
