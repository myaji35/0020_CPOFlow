---
template: plan
version: 1.0
feature: mention
---

# mention Planning Document

> **Summary**: 태스크/코멘트 입력창에서 "@" 입력 시 팀원 드롭다운을 표시하고, 선택된 사용자에게 인앱 알림을 발송하는 멘션 기능
>
> **Project**: CPOFlow
> **Author**: Product Manager Agent
> **Date**: 2026-03-03
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

Order 드로어의 태스크/코멘트 입력창에서 팀원을 "@이름" 형식으로 멘션하여
담당자 지정 및 협업 알림을 즉각 수행한다.
Slack, Linear, GitHub 등의 협업 툴에서 검증된 UX 패턴을 CPOFlow에 적용한다.

### 1.2 Background

현재 CPOFlow는 `Notification` 모델(notification_type 필드 포함)과 `Comment`, `Task`
모델이 이미 구축되어 있으나, 멘션(@) 트리거 및 인앱 알림 발송 연동이 없다.
팀원이 오더 코멘트에 다른 팀원을 태그해 주의를 끌거나,
태스크 생성 시 "@이름"으로 담당자를 즉시 지정하는 요구가 발생했다.

### 1.3 Related Documents

- PRD: `docs/prd.md`
- 기존 Notification 모델: `app/models/notification.rb`
- 기존 Comment 모델: `app/models/comment.rb`
- 기존 Task 모델: `app/models/task.rb`
- Drawer UI: `app/views/orders/_drawer_content.html.erb`

---

## 2. Scope

### 2.1 In Scope

- [x] **태스크 입력창 멘션**: "@" 입력 → 활성 팀원(Employee) 드롭다운 → 선택 → "@이름" 텍스트 삽입 + `assignee_id` 자동 세팅
- [x] **코멘트 입력창 멘션**: "@" 입력 → 활성 팀원 드롭다운 → 선택 → "@이름" 텍스트 삽입 + 인앱 알림 발송
- [x] **팀원 목록 AJAX 검색**: `GET /users/mention_suggestions?q=검색어` 엔드포인트 (JSON 반환)
- [x] **인앱 알림**: 멘션된 `User`에게 `Notification` 레코드 생성 (`notification_type: "mentioned"`)
- [x] **드롭다운 키보드 UX**: 방향키(위/아래) 이동, Enter 선택, Esc 닫기, Tab 닫기
- [x] **Stimulus 컨트롤러**: `mention_controller.js` 단독 컨트롤러로 구현 (재사용 가능)
- [x] **멘션 하이라이트 표시**: 저장된 코멘트/태스크 제목에서 `@이름` 파란 텍스트로 렌더링

### 2.2 Out of Scope

- 멘션 전용 별도 DB 테이블(Mention 모델) 생성 — MVP에서는 body 텍스트 파싱으로 처리
- 이메일 알림 (멘션 → 이메일) — Phase 2 연장
- 멘션 집계 통계/대시보드
- 외부 팀원(고객, 거래처) 멘션
- 슬래시 커맨드(`/status`, `/assign`)
- 리얼타임 푸시(ActionCable) — 새로고침 기반 알림으로 MVP 처리

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | 요구사항 | 우선순위 | 비고 |
|----|----------|----------|------|
| FR-01 | 태스크 입력창에서 "@" 입력 시 활성 팀원 목록 드롭다운 표시 | Must | Employee.active 기준 |
| FR-02 | 코멘트 입력창에서 "@" 입력 시 활성 팀원 목록 드롭다운 표시 | Must | 동일 Stimulus 컨트롤러 재사용 |
| FR-03 | 입력 중인 "@검색어"로 팀원 이름 필터링 (부분 일치, 대소문자 무시) | Must | AJAX `q` 파라미터 |
| FR-04 | 드롭다운 항목 선택 시 "@이름" 텍스트 커서 위치에 삽입 | Must | data-user-id 저장 |
| FR-05 | 태스크 멘션 선택 시 `assignee_id` 자동 설정 (숨김 필드) | Must | Task.assignee 연동 |
| FR-06 | 코멘트 저장 시 body 내 "@이름" 파싱 후 해당 User에게 Notification 생성 | Must | notification_type: "mentioned" |
| FR-07 | 키보드 방향키로 드롭다운 항목 이동, Enter로 선택, Esc/Tab으로 닫기 | Must | 접근성 기본 요건 |
| FR-08 | 저장된 코멘트/태스크 제목에서 "@이름" 파란색 강조 텍스트로 렌더링 | Should | CSS span 치환 |
| FR-09 | 알림 배지 카운트에 "mentioned" 타입 포함 | Should | 기존 Notification 시스템 연동 |
| FR-10 | 멘션 드롭다운에 아바타 이니셜 + 이름 + 직책 표시 | Could | UX 개선 |

### 3.2 Non-Functional Requirements

| 카테고리 | 기준 | 측정 방법 |
|----------|------|-----------|
| 성능 | 팀원 검색 응답 < 200ms | 브라우저 Network 탭 |
| 재사용성 | 태스크/코멘트 양쪽에 동일 Stimulus 컨트롤러 적용 | 코드 중복 없음 확인 |
| 보안 | mention_suggestions 엔드포인트 로그인 필수 | `before_action :authenticate_user!` |
| 호환성 | TailwindCSS CDN 환경에서 빌드 없이 동작 | 개발서버 육안 확인 |

---

## 4. 기존 모델 현황 분석

### 4.1 활용 가능한 기존 자산

| 모델/테이블 | 관련 필드 | 멘션 기능 연관 |
|------------|-----------|---------------|
| `User` | `name`, `display_name`, `initials` | 드롭다운 표시 데이터 |
| `Employee` | `name`, `active`, `user_id` | 멘션 대상 팀원 목록 (`Employee.active`) |
| `Comment` | `body`, `user_id`, `order_id` | 코멘트 본문에 멘션 파싱 대상 |
| `Task` | `title`, `assignee_id` | 태스크 제목 멘션 + assignee 자동 지정 |
| `Notification` | `notification_type`, `user_id`, `title`, `body`, `notifiable` | 멘션 알림 저장 (타입 추가만 필요) |

### 4.2 신규 개발 필요 요소

| 항목 | 설명 |
|------|------|
| `Notification::TYPES`에 `"mentioned"` 추가 | 기존 `%w[due_date status_changed assigned system]` 배열에 추가 |
| `GET /users/mention_suggestions` 라우트 | JSON 응답 엔드포인트 |
| `UsersController#mention_suggestions` 액션 | Employee.active 검색 + User 연동 |
| `mention_controller.js` (Stimulus) | "@" 감지, 드롭다운 렌더, 키보드 처리 |
| `Comment#after_create` 콜백 | 멘션 파싱 → Notification 생성 |
| `_comment.html.erb` 멘션 하이라이트 | `@이름` span 치환 헬퍼 |

---

## 5. 아키텍처 설계 방향

### 5.1 Stimulus 컨트롤러 설계 (`mention_controller.js`)

```
data-controller="mention"
data-mention-url-value="/users/mention_suggestions"
data-mention-mode-value="comment"  | "task"

[입력 이벤트]
  keyup → "@" 감지 → fetch(url?q=검색어)
  → 드롭다운 렌더 (ul.mention-dropdown)
  → 방향키: 선택 이동
  → Enter: 선택 확정 → 텍스트 삽입 + (task면 assignee_id 세팅)
  → Esc/Tab: 드롭다운 닫기
  → clickOutside: 드롭다운 닫기
```

### 5.2 서버 사이드 흐름 (코멘트 저장)

```
POST /orders/:id/comments
  → CommentsController#create
  → Comment 저장
  → after_create: MentionParserService.call(comment)
      → body에서 @이름 파싱
      → User 매칭
      → Notification.create!(
           user: matched_user,
           notification_type: "mentioned",
           title: "#{comment.user.display_name}님이 멘션했습니다",
           body: comment.body.truncate(100),
           notifiable: comment
         )
```

### 5.3 라우트 추가

```ruby
# config/routes.rb
resources :users, only: [] do
  collection do
    get :mention_suggestions
  end
end
```

---

## 6. Success Criteria

### 6.1 Definition of Done

- [ ] FR-01~FR-07 (Must 항목) 전체 구현 완료
- [ ] 태스크 멘션 → assignee 자동 지정 동작 확인
- [ ] 코멘트 멘션 → Notification 레코드 생성 확인 (rails console)
- [ ] 키보드 UX (방향키/Enter/Esc) 정상 동작 확인
- [ ] TailwindCSS CDN 환경에서 드롭다운 UI 정상 표시
- [ ] `bundle exec rubocop` 통과

### 6.2 Quality Criteria

- [ ] `mention_controller.js` 단일 파일로 태스크/코멘트 양쪽 재사용
- [ ] mention_suggestions 응답 200ms 이내
- [ ] N+1 없이 팀원 목록 조회 (`Employee.active.includes(:user)`)

---

## 7. Risks and Mitigation

| 리스크 | 영향 | 발생 가능성 | 대응 방안 |
|--------|------|-------------|-----------|
| Employee-User 비연결 계정 존재 | 멘션 매칭 실패 | 중간 | `Employee.where.not(user_id: nil)` 로 필터, 또는 User 직접 조회 fallback |
| "@" 특수문자 한글 이름 파싱 오류 | 알림 미발송 | 낮음 | 정규식 `/@([\p{L}\w]+)/u` Unicode 지원 |
| 드롭다운이 Drawer overflow에 가려짐 | UX 저하 | 중간 | 드롭다운에 `position: fixed` + `z-index: 9999` 적용 |
| Notification 대량 생성 (같은 사람 반복 멘션) | DB 부하 | 낮음 | 동일 comment에 동일 user 중복 알림 방지 로직 |

---

## 8. Implementation Timeline

| 단계 | 작업 | 예상 소요 |
|------|------|-----------|
| Step 1 | `mention_suggestions` 엔드포인트 + 라우트 추가 | 0.5h |
| Step 2 | `mention_controller.js` Stimulus 컨트롤러 구현 | 1.5h |
| Step 3 | 태스크 입력창 (`tasks/add_form`) Stimulus 연결 | 0.5h |
| Step 4 | 코멘트 입력창 (`comments/form`) Stimulus 연결 | 0.5h |
| Step 5 | `MentionParserService` + `Comment after_create` 콜백 | 1h |
| Step 6 | Notification `TYPES`에 `"mentioned"` 추가 | 0.1h |
| Step 7 | 코멘트/태스크 멘션 하이라이트 헬퍼 | 0.5h |
| Step 8 | 검증 및 rubocop | 0.4h |
| **합계** | | **~5h** |

---

## 9. Next Steps

1. [ ] CTO(팀 리드) Plan 승인
2. [ ] `docs/02-design/features/mention.design.md` 작성 (`/pdca design mention`)
3. [ ] 구현 시작 (`/pdca do mention`)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-03-03 | Initial draft | PM Agent |
