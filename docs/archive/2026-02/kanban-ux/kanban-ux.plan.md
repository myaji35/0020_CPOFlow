# Plan: kanban-ux

## 개요

칸반 보드 UX 개선 — 상단 필터 바 + 카드 퀵액션 추가

## 실측 현황 (2026-02-28)

### 이미 구현된 항목
- SortableJS 드래그 앤 드롭 (drag-handle, group: 'kanban') ✅
- 컬럼 하이라이트 (드래그 중) ✅
- 낙관적 UI + 실패 원위치 복원 ✅
- 이동 토스트 메시지 ✅
- 카드: 우선순위 배지, 납기 배지, 발주처, 프로젝트, 태스크 진행률, 담당자 아바타 ✅
- 카드 클릭 → 드로어 (`openOrderDrawer`) ✅

### 누락 항목
- 상단 필터 바 (담당자 / 우선순위 / 납기 / 키워드) ❌
- 카드 hover 퀵액션 버튼 (다음 단계 이동) ❌

## 기능 요구사항

### FR-01: 상단 필터 바
- **담당자 필터**: 드롭다운 — 내 발주 / 전체 / 특정 담당자
- **우선순위 필터**: 토글 버튼 — 전체 / 긴급 / 높음 / 보통
- **납기 필터**: 토글 버튼 — 전체 / D-7 이내 / 지연
- **키워드 검색**: 인라인 텍스트 필드 (title, customer_name 매칭)
- **필터 초기화** 버튼
- 필터 적용 시 조건에 맞지 않는 카드 `hidden` 처리 (JS, 서버 요청 없음)

### FR-02: 카드 퀵액션 (hover 시 노출)
- **다음 단계 이동 버튼** — 현재 컬럼의 다음 status로 PATCH /orders/:id/move 호출
- **이전 단계 이동 버튼** — 현재 컬럼의 이전 status로 이동 (첫 컬럼은 숨김)
- hover 시 카드 우상단에 슬라이드인 표시
- 이동 성공 시 기존 토스트와 동일한 UX

## 기술 구현 계획

### 컨트롤러 변경 없음
- 필터: 순수 JS (클라이언트 사이드)
- 퀵액션: 기존 `PATCH /orders/:id/move` API 재사용

### 뷰 변경
| 파일 | 변경 | 내용 |
|------|------|------|
| `app/views/kanban/index.html.erb` | 수정 | 상단 필터 바 추가 + 필터 JS 로직 |
| `app/views/kanban/_card.html.erb` | 수정 | 퀵액션 버튼 추가 (hover 노출) |

### 필터 JS 설계
```javascript
function applyFilters() {
  const assignee  = filterAssignee.value;   // user_id or ""
  const priority  = filterPriority.value;   // "" | "urgent" | "high" | "normal"
  const due       = filterDue.value;         // "" | "urgent" | "overdue"
  const keyword   = filterKeyword.value.toLowerCase().trim();

  document.querySelectorAll('[data-order-id]').forEach(card => {
    const match =
      matchAssignee(card, assignee) &&
      matchPriority(card, priority) &&
      matchDue(card, due) &&
      matchKeyword(card, keyword);
    card.closest('[data-order-id]').classList.toggle('hidden', !match);
  });
  updateCounts();
}
```
- 카드에 `data-assignee-ids`, `data-priority`, `data-due-days` 속성 추가 필요

### 퀵액션 버튼 설계
```html
<!-- 카드 우상단 hover 노출 -->
<div class="quick-actions absolute top-2 right-2 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
  <% if prev_status %>
    <button data-move-to="<%= prev_status %>" class="quick-move-btn ...">◀</button>
  <% end %>
  <% if next_status %>
    <button data-move-to="<%= next_status %>" class="quick-move-btn ...">▶</button>
  <% end %>
</div>
```
- `_card.html.erb`에 `prev_status`, `next_status` 로컬 변수 전달 필요
- 카드 컨테이너에 `relative` 클래스 추가

## 영향 범위

| 파일 | 변경 유형 | 내용 |
|------|-----------|------|
| `app/views/kanban/index.html.erb` | 수정 | 필터 바 UI + 필터 JS + render card 시 locals 전달 |
| `app/views/kanban/_card.html.erb` | 수정 | data 속성 추가 + 퀵액션 버튼 + relative 포지셔닝 |

## 완료 기준

- [ ] 담당자/우선순위/납기/키워드 필터 동작
- [ ] 필터 초기화 버튼 동작
- [ ] 카드 hover 시 퀵액션 버튼 노출
- [ ] 퀵액션으로 다음/이전 단계 이동 동작 + 토스트 확인
- [ ] 드래그 앤 드롭 기존 동작 유지
- [ ] Gap Analysis Match Rate ≥ 90%
