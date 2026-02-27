# order-form-ux Plan

## 1. Feature Overview

**Feature Name**: order-form-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (1~2 files)

### 1.1 Summary

주문 신규 생성/수정 폼 UX 개선 — 현재 단순 텍스트 입력 위주의 폼을 슬라이드오버(모달) 방식으로 전환하고, 발주처 선택 시 관련 프로젝트 자동 필터링, 납기일 퀵픽 버튼, 담당자 자동 배정 등 입력 효율을 높인다.

### 1.2 Current State (실측)

**`app/views/orders/new.html.erb`** (14줄):
- `/orders/new` 전체 페이지로 이동하는 방식
- 단순 card + form partial 구조

**`app/views/orders/_form.html.erb`** (163줄):
- 자동완성 Stimulus controller (`autocomplete`) — client, supplier, project에 적용됨
- 검색 라우트: `search_clients_path`, `search_suppliers_path`, `search_projects_path` 존재
- 필드: title, client_id, due_date, supplier_id, project_id, item_name, quantity, estimated_value, priority, tags, description
- `customer_name` validation 존재 (모델) — 폼에 미포함 (버그 가능성)

**문제점**:
1. **전체 페이지 이동**: 칸반/대시보드에서 주문 생성 시 컨텍스트가 끊김
2. **발주처↔프로젝트 연동 없음**: client 선택 후 project 목록이 필터링되지 않음
3. **납기일 입력 불편**: date picker만 있고 "D+7", "D+14", "D+30" 퀵 버튼 없음
4. **customer_name 필드 누락**: 모델 validation은 있는데 폼에 없어 저장 실패 가능
5. **섹션 구분 없음**: 필드들이 나열되어 있어 시각적 그룹핑 부재

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **슬라이드오버 모달**: new/edit 폼을 우측 슬라이드오버로 전환 (전체 페이지 이동 제거) |
| FR-02 | **발주처↔프로젝트 연동**: client 선택 시 project 드롭다운 자동 필터링 |
| FR-03 | **납기일 퀵픽**: "1주", "2주", "1개월" 버튼으로 납기일 빠른 설정 |
| FR-04 | **customer_name 필드 추가**: 모델 validation에 맞게 폼에 포함 |
| FR-05 | **섹션 그룹핑**: 기본정보 / 거래처 / 품목·금액 / 추가정보 4개 섹션으로 시각 구분 |

### Out of Scope
- 품목 다중 추가 (line items)
- 파일 첨부 (별도 기능)
- AI 주문 초안 생성

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/views/orders/_form.html.erb` | customer_name 추가, 섹션 그룹핑, 납기일 퀵픽, 발주처↔프로젝트 연동 JS |
| `app/views/orders/new.html.erb` | 슬라이드오버 레이아웃으로 교체 |
| `app/views/layouts/application.html.erb` | 전역 주문 생성 슬라이드오버 컨테이너 추가 (선택) |

### 3.2 슬라이드오버 구조

```
[우측 슬라이드오버 — max-w-xl]
┌─────────────────────────────┐
│ New Order          [✕]      │
├─────────────────────────────│
│ [기본 정보]                  │
│  - 제목 (full width)         │
│  - 고객사명 (customer_name)  │
│  - 발주처 (autocomplete)     │
├─────────────────────────────│
│ [거래 정보]                  │
│  - 공급사   | 현장/프로젝트  │
│  - 납기일  [1주][2주][1개월] │
├─────────────────────────────│
│ [품목 / 금액]                │
│  - 품목명 | 수량 | 예상금액  │
├─────────────────────────────│
│ [추가 정보]                  │
│  - 우선순위  | 태그          │
│  - 설명                     │
├─────────────────────────────│
│ [Create Order] [Cancel]     │
└─────────────────────────────┘
```

### 3.3 발주처↔프로젝트 연동

client_id 변경 시 `search_projects_path?client_id={id}` 로 재검색:
- autocomplete controller에 `filterParam` value 추가
- client autocomplete 선택 시 project autocomplete의 filter 업데이트

### 3.4 납기일 퀵픽 JS

```javascript
function setDueDate(days) {
  var d = new Date();
  d.setDate(d.getDate() + days);
  document.getElementById('order_due_date').value =
    d.toISOString().split('T')[0];
}
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | new.html.erb가 슬라이드오버 레이아웃으로 전환됨 |
| 2 | customer_name 필드 폼에 포함 |
| 3 | 납기일 옆 "1주 / 2주 / 1개월" 퀵픽 버튼 동작 |
| 4 | 발주처 선택 시 프로젝트 자동완성 필터링 |
| 5 | 4개 섹션(기본정보/거래정보/품목금액/추가정보) 시각 구분 |
| 6 | 폼 제출 후 칸반 페이지로 리다이렉트 (기존 동작 유지) |
| 7 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `autocomplete` Stimulus controller — 기존 존재 (`app/javascript/controllers/autocomplete_controller.js`)
- `search_projects_path` — `?client_id=` 파라미터 지원 여부 확인 필요
- `customer_name` 컬럼 — DB에 존재

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
