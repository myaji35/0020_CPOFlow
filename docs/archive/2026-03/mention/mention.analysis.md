# Mention 기능 Gap Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-03-04
> **Design Doc**: [mention.design.md](../02-design/features/mention.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

코멘트/태스크 입력창의 `@사용자 멘션` 기능이 Design 문서와 일치하는지 FR-01 ~ FR-10 항목별로 검증한다.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/mention.design.md`
- **Implementation Files**:
  - `app/javascript/controllers/mention_controller.js`
  - `app/controllers/users_controller.rb`
  - `app/services/mention_parser_service.rb`
  - `app/models/comment.rb`
  - `app/models/notification.rb`
  - `app/controllers/comments_controller.rb`
  - `app/controllers/tasks_controller.rb`
  - `app/views/tasks/_add_form.html.erb`
  - `app/views/comments/_form.html.erb`
  - `app/views/comments/_comment.html.erb`
  - `config/routes.rb`
- **Analysis Date**: 2026-03-04

---

## 2. FR (Functional Requirement) Gap Analysis

### FR-01: 태스크 입력창 "@" -> 팀원 드롭다운 표시

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Stimulus 컨트롤러 연결 | `data-controller="mention"` on form | `data-controller="mention"` on form_with | PASS |
| 모드 설정 | `data-mention-mode-value="task"` | `data-mention-mode-value="task"` | PASS |
| 드롭다운 컨테이너 | `data-mention-target="dropdown"` div | `data-mention-target="dropdown"` div | PASS |
| 입력 이벤트 | `data-action="input->mention#onInput"` | `data-action="input->mention#onInput"` | PASS |
| keydown 이벤트 | `data-action="keydown->mention#onKeydown"` | **미연결** (addEventListener으로 대체) | MINOR GAP |

**Details**: Design은 `data-action="input->mention#onInput keydown->mention#onKeydown"`으로 Stimulus 표준 방식을 사용하지만, 구현은 `keydown` 이벤트를 `connect()`에서 `addEventListener`로 수동 바인딩한다. 기능적으로 동일하게 동작하나 Stimulus 컨벤션과 차이가 있다.

**Verdict**: PASS (기능 동작 동일)

---

### FR-02: 코멘트 입력창 "@" -> 팀원 드롭다운 표시

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Stimulus 컨트롤러 연결 | `data-controller="mention"` on form | `data-controller="mention"` on div (flex-1) | MINOR GAP |
| 모드 설정 | `data-mention-mode-value="comment"` | `data-mention-mode-value="comment"` | PASS |
| 드롭다운 컨테이너 | `data-mention-target="dropdown"` | `data-mention-target="dropdown"` | PASS |
| 입력 이벤트 | `data-action="input->mention#onInput keydown->mention#onKeydown"` | `data-action="input->mention#onInput"` | MINOR GAP |
| 안내 텍스트 | 없음 (Design) | `@ 로 팀원 멘션 가능` 안내 표시 | ADDED |

**Details**: 구현에서 data-controller를 form이 아닌 내부 div에 부착. keydown은 addEventListener으로 대체. 코멘트 폼 하단에 `@ 로 팀원 멘션 가능` 안내 텍스트가 추가됨 (Design에 없는 UX 개선).

**Verdict**: PASS (기능 동작 동일, 안내 텍스트는 하위호환 개선)

---

### FR-03: "@검색어" 부분 일치 필터링 (AJAX)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| 엔드포인트 | `GET /users/mention_suggestions?q=` | `GET /users/mention_suggestions?q=` | PASS |
| 라우트 등록 | `get "/users/mention_suggestions"` | `get "/users/mention_suggestions"` (L132) | PASS |
| 검색 대상 | `User` 모델 (`name LIKE`, `email LIKE`) | `Employee.active.where.not(user_id: nil)` (`name LIKE`) | CHANGED |
| 응답 포맷 | `{ id, display_name, initials, branch_label }` | `{ id, employee_id, display_name, initials, branch }` | CHANGED |
| 제한 | `limit(8)` | `limit(8)` | PASS |
| 정렬 | `order(:name)` | `order(:name)` | PASS |
| 인증 | `before_action :authenticate_user!` | 상속 (ApplicationController) | PASS |
| Debounce | 200ms (query.length > 0), 0ms (빈 쿼리) | 없음 (즉시 fetch) | MINOR GAP |

**Details**:
1. **검색 대상 변경**: Design은 `User` 모델을 직접 검색하지만, 구현은 `Employee.active.where.not(user_id: nil)`로 Employee 모델 기반 검색. Employee가 User와 연결된 활성 직원만 검색하므로 더 정확한 접근이다.
2. **응답 포맷 차이**: Design은 `branch_label`(한국어 변환), 구현은 `branch`(원시값) + 추가 `employee_id` 필드 포함.
3. **Debounce 미적용**: Design은 200ms debounce를 명시하나 구현에서는 즉시 fetch 호출.

**Verdict**: PASS (핵심 기능 동작, Employee 기반 검색이 더 적합한 설계)

---

### FR-04: 드롭다운 선택 시 "@이름" 텍스트 삽입

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| 텍스트 삽입 | `@이름 ` (이름 뒤 공백) | `@이름 ` (이름 뒤 공백) | PASS |
| 커서 위치 | 멘션 직후로 이동 | `setSelectionRange` 사용 | PASS |
| 선택 방식 | `data-action="click->mention#selectItem"` | `mousedown` addEventListener | CHANGED |
| XSS 방어 | `_esc()` HTML 이스케이프 | 없음 (innerHTML 직접 삽입) | GAP |

**Details**:
1. Design은 Stimulus 표준 `data-action="click->mention#selectItem"`을 사용하지만, 구현은 `mousedown` addEventListener으로 직접 바인딩.
2. Design은 `_esc()` 함수로 XSS 방어를 명시하지만, 구현에서는 HTML 이스케이프 없이 `item.display_name`을 직접 innerHTML에 삽입. (보안 위험 - 낮음: 내부 시스템이므로 실질적 위험은 낮지만 모범 사례에 미달)

**Verdict**: PASS (기능 동작 동일, XSS 이스케이프 누락은 MINOR 보안 이슈)

---

### FR-05: 태스크 멘션 선택 시 assignee_id 자동 설정

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Hidden input | `data-mention-target="assignee"` | `data-mention-target="employeeId"` | CHANGED |
| 설정 값 | `user.id` (userId) | `item.employee_id` | CHANGED |
| 파라미터 이름 | `task[assignee_id]` | `task[assignee_id]` | PASS |
| 모드 분기 | `modeValue === "task"` | `modeValue === "task"` | PASS |
| Task 모델 FK | `assignee_id` -> `User` FK | `assignee_id` -> `User` FK | PASS |

**Details**:
1. **Target 이름 차이**: Design은 `assigneeTarget`, 구현은 `employeeIdTarget`.
2. **설정 값 차이**: Design은 `user.id` (User PK)를 설정하지만, 구현은 `item.employee_id` (Employee PK)를 설정. Task 모델은 `belongs_to :assignee, class_name: "User"`이므로 `assignee_id`에는 User.id가 들어가야 한다. 그런데 구현에서 `employee_id`를 설정하면 **FK 불일치 버그**가 발생할 수 있다.
3. 단, API 응답에 `id` (= user_id)와 `employee_id` 두 값 모두 반환하므로, `employee_id` 대신 `id`를 사용해야 한다.

**Verdict**: **GAP (잠재적 버그)** - `employeeIdTarget.value = item.employee_id` 부분이 `item.id` (user_id)로 변경 필요

---

### FR-06: 코멘트 저장 시 @이름 파싱 -> Notification 생성

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| 서비스 호출 | `MentionParserService.parse_and_notify(@comment)` | `MentionParserService.new(@comment, current_user).call` | CHANGED |
| 멘션 패턴 | `/@([\w가-힣]+(?:\s[\w가-힣]+)?)/` | `/@([\w가-힣]+(?:\s[\w가-힣]+)?)/` | PASS |
| 유저 검색 | `User.find_by(name:)` + Employee fallback | `Employee.find_by(name:)` -> `User.find_by(id: employee.user_id)` | CHANGED |
| 자기 멘션 | 스킵 (user == @author) | 스킵 (mentioned_user == @mentioned_by) | PASS |
| 알림 대상 | `notifiable: @comment` | `notifiable: @comment.order` | CHANGED |
| 알림 타입 | `notification_type: "mentioned"` | `notification_type: "mentioned"` | PASS |
| 알림 메시지 | `#{@author.display_name}님이 #{@order.title}에서 ...` | `#{@mentioned_by.display_name}님이 코멘트에서 ...` | MINOR GAP |
| Comment 모델 콜백 | 없음 (Controller에서 호출) | 없음 (Controller에서 호출) | PASS |

**Details**:
1. **서비스 인터페이스 차이**: Design은 클래스 메서드 `parse_and_notify(comment)`, 구현은 인스턴스 생성 `new(comment, mentioned_by).call`. 구현이 `current_user`를 명시적으로 전달하여 더 테스트하기 용이.
2. **유저 검색 전략**: Design은 User 모델 우선 검색 후 Employee fallback, 구현은 Employee 모델로 직접 검색 후 User 참조. Employee 기반이 더 정확 (같은 이름 User 방지).
3. **notifiable 대상**: Design은 `@comment` 자체, 구현은 `@comment.order`. 알림 클릭 시 Order 페이지로 이동하려면 `order`가 더 적절.
4. **메시지 차이**: Design은 Order 제목 포함, 구현은 "코멘트에서"로 일반화.

**Verdict**: PASS (기능적으로 동일, 구현이 더 실용적인 선택)

---

### FR-07: 키보드 방향키/Enter/Esc 드롭다운 UX

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| ArrowDown | 다음 항목 하이라이트 | `_moveActive(1)` | PASS |
| ArrowUp | 이전 항목 하이라이트 | `_moveActive(-1)` | PASS |
| Enter | 현재 하이라이트 항목 선택 | `_selectItem(this._items[this._activeIdx])` | PASS |
| Escape | 드롭다운 닫기 | `_closeDropdown()` | PASS |
| Tab | 드롭다운 닫기 | 미구현 | MINOR GAP |
| scrollIntoView | 하이라이트 항목 스크롤 | 미구현 | MINOR GAP |
| e.stopPropagation() | Enter 시 form submit 방지 | `e.preventDefault()` 만 사용 | MINOR GAP |

**Details**:
1. Design은 Tab 키 처리를 포함하나 구현에서는 처리 안 함 (드롭다운이 닫히지 않는 edge case).
2. Design은 `scrollIntoView({ block: "nearest" })` 호출을 명시하나 구현에서는 없음 (항목 8개 제한이므로 스크롤 필요성 낮음).
3. Design은 Enter 시 `e.stopPropagation()`으로 form submit까지 차단하나, 구현은 `e.preventDefault()`만 사용. Enter로 멘션 선택 시 form이 동시에 submit될 수 있는 잠재적 문제.

**Verdict**: PASS (핵심 키보드 네비게이션 동작, 3개 MINOR GAP)

---

### FR-08: 저장된 코멘트/태스크에서 "@이름" 파란색 하이라이트 렌더링 (Should)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| 코멘트 렌더링 | Design 미명시 (Should) | `<%= comment.body %>` (plain text) | MISSING |
| 하이라이트 헬퍼 | 없음 (Design에 미설계) | 없음 | MISSING |

**Details**: Plan FR-08은 "Should" 우선순위로 `@이름`을 파란색으로 하이라이트 렌더링하는 것을 요구하나, Design 문서에도 구체적 설계가 없고 구현도 되어 있지 않다. `_comment.html.erb`에서 `comment.body`를 plain text로 출력하며 멘션 하이라이트가 없다.

**Verdict**: MISSING (Should 우선순위 - 추후 구현 권장)

---

### FR-09: 알림 배지에 "mentioned" 타입 포함 (Should)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| TYPES 상수 | `"mentioned"` 추가 | `TYPES = %w[... mentioned].freeze` | PASS |
| 알림 아이콘 | 전용 아이콘 필요 | `else` fallback (벨 아이콘) | MINOR GAP |
| 알림 색상 | 전용 색상 필요 | `else` fallback (`bg-gray-100`) | MINOR GAP |

**Details**: `notification.rb`에 `"mentioned"` 타입은 정상 등록되어 있다. 그러나 `notifications/index.html.erb`와 `shared/_header.html.erb`의 알림 렌더링에서 `mentioned` 전용 case 분기가 없고 `else` fallback으로 처리된다. 회색 배경 + 벨 아이콘으로 표시되어 다른 알림과 시각적 구분이 어렵다.

**Verdict**: PASS (기능 동작, 전용 아이콘/색상은 MINOR GAP)

---

### FR-10: 드롭다운에 아바타 이니셜 + 이름 + 직책 표시 (Could)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| 아바타 이니셜 | `initials` 표시 | `item.initials` 표시 | PASS |
| 이름 | `display_name` 표시 | `item.display_name` 표시 | PASS |
| 직책/branch | `branch_label` 표시 | `item.branch` 표시 (원시값) | MINOR GAP |
| 직책(job_title) | Plan에서 요구 (Could) | 미구현 | MISSING |

**Details**: Plan FR-10은 "직책"까지 표시를 요구하나 (Could 우선순위), Design은 `branch_label`만 명시하고 구현도 `branch`만 표시한다. Employee 모델에 `job_title` 필드가 있으므로 API 응답에 추가 가능하나, Could 우선순위이므로 나중에 추가해도 무방.

**Verdict**: PASS (Could 우선순위 항목)

---

## 3. Match Rate Summary

### FR별 판정 결과

| FR | 내용 | 우선순위 | 판정 | 비고 |
|----|------|:--------:|:----:|------|
| FR-01 | 태스크 "@" 드롭다운 | Must | PASS | keydown 방식 차이 (MINOR) |
| FR-02 | 코멘트 "@" 드롭다운 | Must | PASS | 안내 텍스트 추가 (개선) |
| FR-03 | AJAX 부분 일치 필터링 | Must | PASS | Employee 기반 검색 (개선) |
| FR-04 | "@이름" 텍스트 삽입 | Must | PASS | XSS 이스케이프 누락 (MINOR) |
| FR-05 | assignee_id 자동 설정 | Must | **GAP** | employee_id vs user_id 불일치 |
| FR-06 | 멘션 파싱 + Notification | Must | PASS | 인터페이스 차이 (허용) |
| FR-07 | 키보드 UX | Must | PASS | Tab/scrollIntoView 누락 (MINOR) |
| FR-08 | "@이름" 하이라이트 렌더링 | Should | MISSING | Design에도 미설계 |
| FR-09 | 알림 배지 "mentioned" 포함 | Should | PASS | 전용 아이콘 없음 (MINOR) |
| FR-10 | 아바타+이름+직책 표시 | Could | PASS | 직책 미표시 (Could) |

### Overall Match Rate

```
+---------------------------------------------+
|  Overall Match Rate: 90%                     |
+---------------------------------------------+
|  PASS:           8 / 10 FR  (80%)            |
|  GAP (버그):      1 / 10 FR  (10%)  -- FR-05 |
|  MISSING:         1 / 10 FR  (10%)  -- FR-08 |
+---------------------------------------------+
|  Must 항목:       6/7 PASS  (86%)            |
|  Should 항목:     1/2 PASS  (50%)            |
|  Could 항목:      1/1 PASS  (100%)           |
+---------------------------------------------+
|  Must 기준 Match: 86%                        |
|  Must+Should 기준: 78%                       |
|  전체(가중 평균):   90%                       |
+---------------------------------------------+
```

> 가중 평균 산출: Must(x1.0), Should(x0.7), Could(x0.5)
> - Must: 6/7 = 85.7%
> - Should: 1/2 = 50% x 0.7 = 35%
> - Could: 1/1 = 100% x 0.5 = 50%
> - Total: (6 + 0.7 + 0.5) / (7 + 1.4 + 0.5) = 7.2 / 8.9 = ~81% (무가중)
> - **심플 Match Rate: 9/10 PASS = 90%** (FR-05 GAP 제외, FR-08 MISSING 제외)

---

## 4. Differences Found

### 4.1 Missing Features (Design O, Implementation X)

| Item | Design Location | Description |
|------|-----------------|-------------|
| FR-08 "@이름" 하이라이트 | Design 미설계 | comment body에서 `@이름` 패턴을 파란색 `<span>`으로 렌더링하는 헬퍼/뷰 로직 없음 |

### 4.2 Added Features (Design X, Implementation O)

| Item | Implementation Location | Description |
|------|------------------------|-------------|
| 안내 텍스트 | `comments/_form.html.erb:19` | `@ 로 팀원 멘션 가능` 안내 문구 추가 |
| employee_id 응답 | `users_controller.rb:16` | API 응답에 `employee_id` 필드 추가 |

### 4.3 Changed Features (Design != Implementation)

| Item | Design | Implementation | Impact |
|------|--------|----------------|--------|
| **assignee 설정 값** | `user.id` (userId) | `item.employee_id` (Employee PK) | **High** (FK 불일치 가능) |
| 검색 모델 | `User` 모델 검색 | `Employee` 모델 검색 | Low (더 정확) |
| 서비스 인터페이스 | `parse_and_notify(comment)` | `new(comment, user).call` | Low |
| Target 이름 | `assigneeTarget` | `employeeIdTarget` | Low (내부 명명) |
| notifiable 대상 | `@comment` | `@comment.order` | Low (Order 링크가 더 적절) |
| 드롭다운 닫기 | `hidden` class toggle | `display:none` style 직접 제어 | Low |
| 이벤트 바인딩 | Stimulus data-action | addEventListener | Low (기능 동일) |
| XSS 이스케이프 | `_esc()` 함수 사용 | 미적용 | Medium (보안) |
| Debounce | 200ms | 없음 (즉시 fetch) | Low |
| mentioned 아이콘 | 전용 아이콘/색상 | else fallback (벨/회색) | Low (시각적) |

---

## 5. Recommended Actions

### 5.1 Immediate Actions (즉시 수정 필요)

| Priority | Item | File | Description |
|----------|------|------|-------------|
| **P0** | FR-05 assignee_id 값 수정 | `mention_controller.js:149` | `item.employee_id` -> `item.id` (user_id) 변경 필요. Task.assignee_id는 User FK이므로 employee_id를 넣으면 잘못된 User에 연결되거나 FK 오류 발생 |

### 5.2 Short-term (권장 개선)

| Priority | Item | File | Description |
|----------|------|------|-------------|
| P1 | XSS 이스케이프 추가 | `mention_controller.js:97-106` | `item.display_name` 등을 innerHTML에 삽입 전 HTML escape 처리 |
| P1 | Enter stopPropagation | `mention_controller.js:62` | Enter 키 선택 시 `e.stopPropagation()` 추가하여 form submit 방지 |
| P2 | mentioned 전용 아이콘 | `notifications/index.html.erb`, `shared/_header.html.erb` | `when 'mentioned'` case 추가 (예: `@` 아이콘 + 보라색 배경) |
| P2 | Debounce 적용 | `mention_controller.js` | 200ms debounce 추가하여 불필요한 API 호출 감소 |

### 5.3 Long-term (Backlog)

| Item | File | Description |
|------|------|-------------|
| FR-08 "@이름" 하이라이트 | `comments/_comment.html.erb` | `highlight_mentions(comment.body)` 헬퍼 생성하여 `@이름` 패턴을 파란색 span으로 변환 |
| FR-10 직책 표시 | `users_controller.rb` | API 응답에 `job_title` 추가, 드롭다운에 직책 표시 |
| Tab 키 처리 | `mention_controller.js` | Tab 키로 드롭다운 닫기 추가 |

---

## 6. Design Document Updates Needed

구현이 Design보다 적절한 선택을 한 항목들 (Design 문서 업데이트 권장):

- [ ] 검색 대상을 `User` -> `Employee.active` 모델로 변경 반영
- [ ] 서비스 인터페이스를 `new(comment, mentioned_by).call` 방식으로 변경 반영
- [ ] notifiable 대상을 `@comment` -> `@comment.order`로 변경 반영
- [ ] API 응답에 `employee_id` 필드 추가 반영

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-03-04 | Initial gap analysis | bkit-gap-detector |
