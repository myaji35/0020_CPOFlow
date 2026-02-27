# drawer-ux Plan

## 1. Feature Overview

**Feature Name**: drawer-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (1~2 files)

### 1.1 Summary

주문 드로어 UX 개선 — 현재 단일 스크롤 뷰로 구성된 드로어를 탭 구조로 개편하여 정보 접근성을 높이고, 헤더에 빠른 상태 변경 버튼을 추가한다.

### 1.2 Current State (실측)

**`orders/_drawer_content.html.erb`** (352줄):
현재 단일 스크롤 구조:
1. 헤더 메타 정보 (배지, 고객사, 마감일, 품목, 금액 등)
2. 담당자 + 스테이지 이동 (grid 2-col)
3. 이메일 원문 (있을 때만)
4. 태스크 체크리스트 (Turbo Frame)
5. 코멘트 (Turbo Stream)
6. 활동 로그 타임라인

**`layouts/application.html.erb`** (드로어 구조):
- 헤더: 제목 + "전체 화면" 링크 + 닫기 버튼
- 바디: `fetch(orderPath + '?drawer=1')` → `#order-drawer-content` 주입

**문제점**:
1. **단일 스크롤**: 콘텐츠가 길어 태스크/코멘트 도달까지 많은 스크롤 필요
2. **스테이지 이동**: 드로어 상단이 아닌 중간에 위치 — 빠른 상태 변경 불편
3. **우선순위 변경**: 인라인 편집 없음 (전체 화면 이동 필요)
4. **탭 없음**: 상세/태스크/코멘트/히스토리를 한 번에 모두 보여줌

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **탭 구조**: 상세 / 태스크 / 코멘트 / 히스토리 4개 탭 |
| FR-02 | **드로어 헤더 빠른 액션**: 다음 스테이지 버튼 + 우선순위 배지 클릭 변경 |
| FR-03 | **우선순위 인라인 변경**: 배지 클릭 → 드롭다운 선택 |

### Out of Scope
- 드로어 내 새 주문 생성
- 파일 첨부
- AI 답변 초안 (별도 기능)

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/views/orders/_drawer_content.html.erb` | 탭 구조 도입 (FR-01) + 우선순위 인라인 (FR-03) |
| `app/views/layouts/application.html.erb` | 드로어 헤더 빠른 액션 버튼 (FR-02) |

### 3.2 탭 구조 설계 (JS 기반, 서버 요청 없음)

4개 탭 — 클릭 시 해당 섹션만 표시:

```
[상세] [태스크] [코멘트] [히스토리]
  ↓       ↓        ↓        ↓
 메타   체크리스트  댓글   활동로그
 담당자
 이메일
```

탭 전환: JS `display` 토글 (Turbo/서버 요청 없음)

### 3.3 드로어 헤더 빠른 액션 (FR-02)

현재 헤더 (layouts/application.html.erb):
```
[제목]          [전체화면] [닫기]
```

변경 후:
```
[제목 + 현재상태배지]    [다음단계→] [전체화면] [닫기]
```

- "다음단계" 버튼: 현재 상태의 다음 Kanban 스테이지로 바로 이동
- `data-order-status` 속성을 `openOrderDrawer` 시 주입
- `delivered` 상태이면 버튼 숨김

### 3.4 우선순위 인라인 변경 (FR-03)

메타 영역의 priority_badge → 클릭 시 드롭다운:

```erb
<div class="relative" id="priority-inline-<%= order.id %>">
  <%= priority_badge(order) %> ← onclick으로 드롭다운 토글
  <div class="hidden absolute ...드롭다운...">
    <% [:low, :normal, :high, :urgent].each do |p| %>
      <%= form_with url: ..., method: :patch ... %> 선택 시 제출
    <% end %>
  </div>
</div>
```

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | 드로어 내 상세/태스크/코멘트/히스토리 4개 탭 표시 |
| 2 | 탭 클릭 시 해당 섹션만 표시 (JS 전환, 서버 요청 없음) |
| 3 | 기본 탭은 "상세" |
| 4 | 드로어 헤더에 "다음 단계 →" 빠른 버튼 표시 |
| 5 | "다음 단계" 버튼 클릭 → 다음 Kanban 스테이지로 상태 변경 |
| 6 | 우선순위 배지 클릭 → 드롭다운으로 변경 가능 |
| 7 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `move_status_order_path` 라우트 — 기존 존재
- `Order::KANBAN_COLUMNS` — 기존 존재
- `priority_badge()` helper — 기존 존재
- Turbo Frame (`task-list-*`, `comments-*`) — 탭 전환 후에도 동작 유지 필요

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
