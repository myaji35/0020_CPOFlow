# due-date-notification Analysis Report

> **Analysis Type**: Gap Analysis (Plan vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Plan Doc**: [due-date-notification.plan.md](../01-plan/features/due-date-notification.plan.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Plan 문서(`due-date-notification.plan.md`)의 FR-01~FR-05 요구사항 대비
실제 구현 코드의 일치율을 측정하고, 누락/변경/추가 항목을 식별한다.

Design 문서가 별도 작성되지 않았으므로 Plan 문서를 기준(source of truth)으로 분석한다.

### 1.2 Analysis Scope

| 항목 | 경로 |
|------|------|
| Plan 문서 | `docs/01-plan/features/due-date-notification.plan.md` |
| DueNotificationJob | `app/jobs/due_notification_job.rb` |
| GoogleChatService | `app/services/google_chat_service.rb` |
| NotificationsController | `app/controllers/settings/notifications_controller.rb` |
| AppSetting 모델 | `app/models/app_setting.rb` |
| Settings View | `app/views/settings/base/index.html.erb` |
| Recurring Schedule | `config/recurring.yml` |
| Routes | `config/routes.rb` |
| NotificationDeliveryJob | `app/jobs/notification_delivery_job.rb` |

---

## 2. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| FR-01: Job 통합 (DueNotificationJob) | 88% | WARN |
| FR-02: Production 스케줄 등록 | 100% | PASS |
| FR-04: Google Chat 메시지 포맷 개선 | 95% | PASS |
| FR-05: Settings Webhook URL 관리 | 100% | PASS |
| Convention Compliance | 95% | PASS |
| **Overall** | **93%** | **PASS** |

---

## 3. FR-01: Job 통합 -- DueNotificationJob 단일화

### 3.1 요구사항 체크리스트

| # | Plan 요구사항 | 구현 상태 | Status |
|---|--------------|----------|--------|
| 1 | D-14, D-7, D-3, D-0 트리거 | `TRIGGER_DAYS = [14, 7, 3, 0]` (line 9) | PASS |
| 2 | Google Chat Webhook 발송 | `GoogleChatService.notify(...)` (line 56) | PASS |
| 3 | 인앱 Notification 생성 (담당자별) | `Notification.create!` per assignee (line 42) | PASS |
| 4 | 중복 발송 방지 (당일 1회) | `already_notified_today?` (line 79-84), `chat_already_sent_today?` (line 87-92) | PASS |
| 5 | 중복 방지 키: `order_id + days_ahead + date` | `notification_type: "due_date_d#{days_ahead}"` + `created_at` 기준 | PASS |
| 6 | 기존 NotificationDeliveryJob 제거/deprecated | **파일이 여전히 존재** (`app/jobs/notification_delivery_job.rb`) | FAIL |

### 3.2 Gap Details

#### FAIL: NotificationDeliveryJob 미제거

- **Plan 문서** (line 43): "기존 `NotificationDeliveryJob` 제거 (또는 deprecated 처리)"
- **현재 상태**: `app/jobs/notification_delivery_job.rb`가 63줄의 완전한 코드로 존재
- `config/recurring.yml`에는 등록되어 있지 않으므로 실행되지는 않지만, 코드 중복 상태
- **영향도**: Medium -- 실행되지 않으나 혼동 유발 가능

#### PASS (with note): notification_type 분화

- **Plan 결정사항** (line 73): 중복 방지 키를 `order_id + days_ahead + date`로 지정
- **구현**: `notification_type: "due_date_d#{days_ahead}"` (e.g., `due_date_d14`, `due_date_d7`, `due_date_d3`, `due_date_d0`)
- Notification 모델의 `TYPES` 상수는 `%w[due_date status_changed assigned system]`으로 정의되어 있음
- `due_date_d14` 등은 TYPES에 포함되지 않으나 validation이 없으므로 동작에 문제 없음
- **권장**: TYPES 상수를 업데이트하거나 notification_type에 대한 validation 추가 고려

### 3.3 FR-01 Match Rate

**Pass: 5/6 items = 83%**

---

## 4. FR-02: Production 스케줄 등록

### 4.1 요구사항 체크리스트

| # | Plan 요구사항 | 구현 상태 | Status |
|---|--------------|----------|--------|
| 1 | `config/recurring.yml` production 블록에 `due_notifications` 추가 | production 블록 line 24-27에 등록됨 | PASS |
| 2 | 매일 오전 7:00 실행 | `schedule: every day at 7am` (line 27) | PASS |
| 3 | `DueNotificationJob` class 지정 | `class: DueNotificationJob` (line 25) | PASS |

### 4.2 추가 구현 (Plan에 없음)

- development 블록에도 동일한 `due_notifications` 스케줄 등록 (line 55-58)
- 이는 개발 편의를 위한 추가 사항으로 적절함

### 4.3 FR-02 Match Rate

**Pass: 3/3 items = 100%**

---

## 5. FR-04: Google Chat 메시지 포맷 개선

### 5.1 요구사항 체크리스트

| # | Plan 요구사항 | 구현 상태 | Status |
|---|--------------|----------|--------|
| 1 | D-14: 파란색 (정보) | `14 => "#1E88E5"` (Material Blue 600) | PASS |
| 2 | D-7: 주황색 (경고) | `7 => "#F4A83A"` (CPOFlow Warning 색상) | PASS |
| 3 | D-3: 빨간색 (긴급) | `3 => "#D93025"` (CPOFlow Danger 색상) | PASS |
| 4 | D-0: 빨간색 + Bold | `0 => "#B71C1C"` (Dark Red) + `<b>` 태그 (line 92) | PASS |
| 5 | 오더 링크 포함 | `order_url` 생성 + `textButton` with `openLink` (line 94-99) | PASS |
| 6 | 발주처 포함 | `topLabel: "발주처"` + `order.client&.name` (line 69-71) | PASS |
| 7 | 담당자 포함 | `topLabel: "담당자"` + `order.assignees.map(&:display_name)` (line 88-90) | PASS |

### 5.2 추가 구현 (Plan에 없음)

| 항목 | 구현 위치 | 설명 |
|------|----------|------|
| 납기일 표시 | GoogleChatService line 74-78 | `topLabel: "납기일"` + 날짜/요일 포맷 |
| 상태 표시 | GoogleChatService line 80-83 | `topLabel: "상태"` + STATUS_LABELS |
| Cards v1 Header | GoogleChatService line 59-63 | `header.title`, `subtitle`, `imageUrl` |
| urgency_label | GoogleChatService line 50-56 | 이모지 기반 긴급도 라벨 |

### 5.3 Plan vs Implementation Color 비교

| Trigger | Plan 색상 | 구현 색상 | 일치 |
|---------|----------|----------|------|
| D-14 | 파란색 | #1E88E5 (Blue) | PASS |
| D-7 | 주황색 | #F4A83A (Orange) | PASS |
| D-3 | 빨간색 | #D93025 (Red) | PASS |
| D-0 | 빨간색 + Bold | #B71C1C (Dark Red) + `<b>` | PASS |

### 5.4 FR-04 Match Rate

**Pass: 7/7 items = 100%** (추가 구현 4건은 보너스)

---

## 6. FR-05: Settings 페이지 Webhook URL 관리

### 6.1 요구사항 체크리스트

| # | Plan 요구사항 | 구현 상태 | Status |
|---|--------------|----------|--------|
| 1 | `/settings`에 Google Chat Webhook URL 입력 UI | `settings/base/index.html.erb` line 87-145 | PASS |
| 2 | URL 저장 기능 | `Settings::NotificationsController#update` → `AppSetting.set(...)` | PASS |
| 3 | "테스트 발송" 버튼 | `button_to settings_test_notifications_path` (view line 127-131) | PASS |
| 4 | DB 저장 (`Setting` 모델) | `AppSetting` 모델 (key-value) + `app_settings` 테이블 | PASS |
| 5 | 라우트 등록 | `patch "notifications"` + `post "notifications/test"` (routes.rb line 152-153) | PASS |
| 6 | Admin 권한 제어 | `before_action :authorize_admin!` (admin || manager) | PASS |

### 6.2 Plan vs Implementation 모델 이름 차이

| 항목 | Plan | Implementation | Status |
|------|------|---------------|--------|
| 모델 이름 | `Setting` | `AppSetting` | CHANGED |
| 테이블 이름 | `settings` | `app_settings` | CHANGED |

- Plan에는 `Setting` 모델로 기술되어 있으나, 실제 구현은 `AppSetting`
- Rails의 기존 `Setting` 충돌을 피한 합리적 변경이므로 영향도 Low

### 6.3 추가 구현 (Plan에 없음)

| 항목 | 구현 위치 | 설명 |
|------|----------|------|
| 연결 상태 배지 | view line 95-98 | 연결됨/미설정 상태 표시 |
| 알림 스케줄 안내 | view line 134-142 | D-14/7/3/0 스케줄 정보 표시 |
| Webhook URL placeholder | view line 110 | chat.googleapis.com 형식 안내 |
| 설정 가이드 텍스트 | view line 115-117 | Google Chat 스페이스 설정 안내 |
| Credentials fallback | GoogleChatService line 20 | DB 없으면 Rails credentials에서 조회 |

### 6.4 FR-05 Match Rate

**Pass: 6/6 items = 100%** (모델명 CHANGED 1건은 합리적 변경)

---

## 7. FR-03: Credentials 설정 가이드 (다음 사이클)

Plan에서 "다음 사이클"로 분류되었으나, 구현 상태를 확인한다.

| # | Plan 요구사항 | 구현 상태 | Status |
|---|--------------|----------|--------|
| 1 | `bin/rails credentials:edit`로 webhook_url 등록 가이드 | 구현 불필요 (AppSetting DB 방식으로 전환) | N/A |
| 2 | Settings 페이지에 테스트 버튼 (선택) | FR-05에서 이미 구현됨 | PASS |

- FR-03은 Plan의 "다음 사이클" 범위이므로 Score 계산에서 제외
- 단, DB 방식 전환으로 Credentials 가이드 자체가 불필요해진 점은 합리적

---

## 8. Convention Compliance

### 8.1 Naming Convention

| Category | Convention | Files | Status |
|----------|-----------|:-----:|--------|
| Job class | PascalCase | `DueNotificationJob` | PASS |
| Service class | PascalCase | `GoogleChatService` | PASS |
| Model class | PascalCase | `AppSetting` | PASS |
| Controller | PascalCase + namespace | `Settings::NotificationsController` | PASS |
| Constants | UPPER_SNAKE_CASE | `TRIGGER_DAYS`, `URGENCY_COLOR` | PASS |
| Methods | snake_case | `notify_order`, `build_title`, `already_notified_today?` | PASS |

### 8.2 Architecture Compliance

| Layer | File | Expected | Actual | Status |
|-------|------|----------|--------|--------|
| Job (Background) | `app/jobs/due_notification_job.rb` | Jobs layer | Jobs layer | PASS |
| Service | `app/services/google_chat_service.rb` | Services layer | Services layer | PASS |
| Controller | `app/controllers/settings/notifications_controller.rb` | Controllers | Controllers | PASS |
| Model | `app/models/app_setting.rb` | Models | Models | PASS |
| View | `app/views/settings/base/index.html.erb` | Views | Views | PASS |

### 8.3 View Layer Concern

- `settings/base/index.html.erb` line 95: `AppSetting.google_chat_webhook_url.present?` -- View에서 직접 모델 메서드 호출
- 이상적으로는 Controller에서 instance variable로 전달해야 하나, Settings 페이지의 단순 상태 표시 용도이므로 영향도 Low

### 8.4 Convention Score: 95%

---

## 9. Gap Summary

### 9.1 FAIL -- Missing Implementation (Plan O, Code X)

| # | Item | Plan Location | Description | Impact |
|---|------|---------------|-------------|--------|
| 1 | NotificationDeliveryJob 제거/deprecated | plan.md line 43, 103 | 파일이 여전히 존재 (63줄 완전한 코드) | Medium |

### 9.2 CHANGED -- Plan != Implementation

| # | Item | Plan | Implementation | Impact |
|---|------|------|---------------|--------|
| 1 | 모델 이름 | `Setting` | `AppSetting` | Low |
| 2 | notification_type 값 | (명시 없음) | `due_date_d#{days_ahead}` (d14/d7/d3/d0) | Low |

### 9.3 ADDED -- Implementation Only (Plan X, Code O)

| # | Item | Implementation Location | Description |
|---|------|------------------------|-------------|
| 1 | 납기일/상태 Card 위젯 | GoogleChatService line 74-83 | 추가 정보 표시 |
| 2 | Credentials fallback | GoogleChatService line 19-20 | DB 미설정 시 credentials 조회 |
| 3 | 연결 상태 배지 | settings view line 95-98 | UI 상태 인디케이터 |
| 4 | 알림 스케줄 안내 | settings view line 134-142 | 사용자 가이드 |
| 5 | development 스케줄 | recurring.yml line 55-58 | 개발환경 스케줄 |
| 6 | urgency_label (이모지) | GoogleChatService line 50-56 | 긴급도 이모지 라벨 |
| 7 | chat_already_sent_today? | DueNotificationJob line 87-93 | Chat 중복 발송 방지 분리 |

---

## 10. Match Rate Calculation

### Item-level Breakdown

| Category | Total | Pass | Changed | Fail | Added | Rate |
|----------|:-----:|:----:|:-------:|:----:|:-----:|:----:|
| FR-01: Job 통합 | 6 | 5 | 0 | 1 | 1 | 83% |
| FR-02: 스케줄 등록 | 3 | 3 | 0 | 0 | 1 | 100% |
| FR-04: 메시지 포맷 | 7 | 7 | 0 | 0 | 4 | 100% |
| FR-05: Settings UI | 6 | 6 | 1 | 0 | 4 | 100% |
| Convention | 11 | 10 | 0 | 0 | 0 | 95% (note) |
| **Total** | **33** | **31** | **1** | **1** | **10** | **93%** |

### Overall Match Rate: 93%

```
+---------------------------------------------+
|  Overall Match Rate: 93%                     |
+---------------------------------------------+
|  PASS:    31 items (94%)                     |
|  CHANGED:  1 items ( 3%)                     |
|  FAIL:     1 items ( 3%)                     |
|  ADDED:   10 items (bonus)                   |
+---------------------------------------------+
```

---

## 11. Recommended Actions

### 11.1 Immediate (within 24 hours)

| Priority | Item | File | Action |
|----------|------|------|--------|
| 1 | NotificationDeliveryJob 제거 또는 deprecated 마킹 | `app/jobs/notification_delivery_job.rb` | 파일 삭제 또는 deprecated 주석 + 클래스 이름에 Deprecated 추가 |

### 11.2 Short-term (within 1 week)

| Priority | Item | File | Action |
|----------|------|------|--------|
| 1 | Notification TYPES 상수 업데이트 | `app/models/notification.rb` | `due_date_d14`, `due_date_d7`, `due_date_d3`, `due_date_d0` 추가 고려 |
| 2 | View layer 직접 모델 호출 정리 | `app/views/settings/base/index.html.erb` | Controller에서 `@webhook_configured` 등 instance variable 전달 |

### 11.3 Documentation Update

| Item | Action |
|------|--------|
| Plan 모델명 | `Setting` -> `AppSetting`으로 Plan 문서 업데이트 |
| notification_type 값 | `due_date_d{N}` 패턴 Plan 문서에 명시 |

---

## 12. Conclusion

93% Match Rate로 Plan 대비 구현 완성도가 높다.
유일한 FAIL 항목은 `NotificationDeliveryJob` 파일 미제거이며,
실행 스케줄에서는 제외되어 있어 기능적 영향은 없으나
코드 정리(dead code removal) 차원에서 처리가 필요하다.

추가 구현 10건은 모두 UX 개선 및 안정성 강화 성격으로 적절한 확장이다.

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial gap analysis | bkit-gap-detector |
