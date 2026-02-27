# Plan: order-drawer-enhancement

## Feature Overview
오더 상세 드로어의 3가지 핵심 UX를 고도화한다:
1. **태스크 체크리스트 — Hotwire Turbo 인라인 토글** (현재: form full-submit)
2. **코멘트 스레드 — Turbo Stream 실시간 추가** (현재: full-page reload)
3. **활동 로그 — 타임라인 UI 개선** (현재: 단순 텍스트 목록)

## Problem Statement
- 태스크 체크박스 클릭 시 전체 페이지 리로드 → UX 끊김
- 코멘트 작성 후 전체 페이지 리로드 → 스크롤 위치 초기화
- 활동 로그가 단순 텍스트 나열 → 가독성 낮음

## Goals
1. 태스크 완료 토글: 체크박스 클릭 → 서버 업데이트 → 해당 항목만 교체 (Turbo Frame)
2. 코멘트 등록: 작성 후 → 스트림으로 목록 맨 아래 추가 (Turbo Stream)
3. 활동 로그: 상태 변경·코멘트·태스크 완료를 타임라인 형태로 시각화

## Scope

### In Scope
- `_drawer_content.html.erb` — 태스크/코멘트/활동 섹션 수정
- `tasks_controller.rb` — update 액션에 turbo_stream 응답 추가
- `comments_controller.rb` — create 액션에 turbo_stream 응답 추가
- 활동 로그 타임라인 UI (상태변경·코멘트·태스크 아이콘 구분)

### Out of Scope
- ActionCable 실시간 멀티유저 동기화 (Phase 2)
- 태스크 드래그앤드롭 순서 변경
- 코멘트 수정/삭제

## Technical Approach

### 1. 태스크 Turbo Frame 토글
```erb
<turbo-frame id="task-<%= task.id %>">
  form_with url: order_task_path, data: { turbo: true }
  체크박스 onchange → form auto-submit
</turbo-frame>
```
TasksController#update → turbo_stream.replace "task-#{task.id}"

### 2. 코멘트 Turbo Stream
```erb
<div id="comments-<%= order.id %>">코멘트 목록</div>
form_with data: { turbo: true }
```
CommentsController#create → turbo_stream.append "comments-#{order.id}"
→ textarea 자동 초기화 + 스크롤

### 3. 활동 로그 타임라인
- 상태변경: 화살표 아이콘 + 컬러 배지 (from → to)
- 코멘트 작성: 말풍선 아이콘
- 태스크 완료: 체크 아이콘
- 시간순 정렬, 날짜 구분선

## Acceptance Criteria
- [ ] 태스크 체크박스 클릭 → 페이지 리로드 없이 해당 행만 업데이트
- [ ] 진행률 바도 함께 갱신
- [ ] 코멘트 등록 → 목록 맨 아래 새 코멘트 추가, textarea 초기화
- [ ] 활동 로그에 아이콘/컬러로 행동 유형 구분
- [ ] 다크모드 대응

## Implementation Order
1. TasksController#update — turbo_stream 응답
2. _drawer_content.html.erb — 태스크 turbo-frame 래핑
3. CommentsController#create — turbo_stream 응답
4. _drawer_content.html.erb — 코멘트 turbo-stream 영역
5. 활동 로그 타임라인 UI 개선
