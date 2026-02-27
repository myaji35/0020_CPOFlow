# Feature Plan: due-date-notification

**Feature Name**: 납기일 Google Chat 알림
**Created**: 2026-02-28
**Phase**: Plan
**Priority**: HIGH

---

## 개요

납기일이 임박한 발주 건을 Google Chat Webhook으로 팀에 자동 알림한다.
`GoogleChatService`와 `NotificationDeliveryJob`이 이미 구현되어 있으나,
Credentials 미설정 + Production 스케줄 미등록 + Job 중복 문제로 실제 동작하지 않는 상태.

---

## 현재 상태 (AS-IS)

| 항목 | 상태 | 비고 |
|------|------|------|
| `GoogleChatService` | ✅ 구현됨 | Faraday, Card 포맷 |
| `NotificationDeliveryJob` | ✅ 구현됨 | D-7/3/0, Google Chat + Notification 생성 |
| `DueNotificationJob` | ⚠️ 이메일 전용 | D-14/7/3/0, OrderMailer만 호출 |
| `config/recurring.yml` production | ❌ 스케줄 없음 | development만 DueNotificationJob 등록 |
| Google Chat credentials | ❌ 미설정 | `webhook_url` = nil |
| D-14 Google Chat 알림 | ❌ 없음 | NotificationDeliveryJob은 D-7/3/0만 |

### Job 중복 문제
- `DueNotificationJob`: 이메일 전용, D-14/7/3/0
- `NotificationDeliveryJob`: Google Chat + Notification 생성, D-7/3/0
- 역할이 겹치며 하나로 통합 필요

---

## 목표 (TO-BE)

### FR-01: Job 통합 — `DueNotificationJob` 단일화
- D-14, D-7, D-3, D-0 트리거
- Google Chat Webhook 발송 (채널: 팀 공용)
- 인앱 Notification 생성 (담당자별)
- 중복 발송 방지 (당일 이미 발송된 경우 skip)
- 기존 `NotificationDeliveryJob` 제거 (또는 deprecated 처리)

### FR-02: Production 스케줄 등록
- `config/recurring.yml` production 블록에 `due_notifications` 추가
- 매일 오전 7:00 실행

### FR-03: Google Chat Credentials 설정 가이드
- `bin/rails credentials:edit` 로 `google_chat.webhook_url` 등록
- Settings 페이지에 Webhook URL 테스트 버튼 추가 (선택)

### FR-04: Google Chat 메시지 포맷 개선
- D-14: 파란색 (정보) — "납기 2주 전 알림"
- D-7:  주황색 (경고) — "납기 1주 전 알림"
- D-3:  빨간색 (긴급) — "납기 3일 전 알림"
- D-0:  빨간색 + Bold — "오늘 납기!"
- 오더 링크, 발주처, 담당자 포함

### FR-05: Settings 페이지 — Webhook URL 관리
- `/settings` 에 Google Chat Webhook URL 입력/저장 UI
- "테스트 발송" 버튼으로 즉시 테스트
- DB 저장 (`settings` 테이블 or credentials)

---

## 기술 결정

| 항목 | 결정 | 이유 |
|------|------|------|
| Webhook URL 저장 위치 | `Setting` 모델 (DB) | Rails credentials는 재배포 필요, DB가 더 유연 |
| Job 통합 방향 | `DueNotificationJob` 확장 | 이미 스케줄 등록됨, 이름이 명확 |
| 중복 방지 키 | `order_id + days_ahead + date` | 날짜 기반으로 당일 1회만 |
| Chat API 버전 | Incoming Webhook (v1) | Simple, no OAuth needed |
| 색상 구분 | Google Chat Card `header.imageStyle` + text color | Cards v1 지원 범위 내 |

---

## 구현 범위 (이번 사이클)

**포함**
- FR-01: DueNotificationJob Google Chat 통합
- FR-02: Production 스케줄 등록
- FR-04: 메시지 포맷 개선 (D별 색상/긴급도)
- FR-05: Settings 페이지 Webhook URL 저장 + 테스트

**다음 사이클**
- FR-03: Credentials 가이드 문서
- 채널 다중화 (HR 채널, 영업 채널 분리)

---

## 연관 파일

| 파일 | 변경 유형 |
|------|---------|
| `app/jobs/due_notification_job.rb` | 수정 — Google Chat + Notification 통합 |
| `app/services/google_chat_service.rb` | 수정 — D별 색상/포맷 개선 |
| `config/recurring.yml` | 수정 — production 스케줄 추가 |
| `app/models/setting.rb` | 신규 또는 수정 — webhook_url 저장 |
| `app/controllers/settings_controller.rb` | 수정 — webhook 저장/테스트 액션 |
| `app/views/settings/index.html.erb` | 수정 — Webhook UI 추가 |
| `app/jobs/notification_delivery_job.rb` | 제거 또는 deprecated |
