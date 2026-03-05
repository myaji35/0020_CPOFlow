# card-merge Planning Document

> **Summary**: 동일 이벤트 번호(reference_no)의 Order 카드를 1개 메인 카드로 병합하고 서브 이벤트는 히스토리로 보존한다.
>
> **Project**: CPOFlow
> **Author**: PM Agent
> **Date**: 2026-03-03
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

ARIBA 등 외부 조달 시스템에서 동일 이벤트(예: `6000009460`)에 대해 "has changed", "has been reopened", "is no longer accepting responses" 등 여러 이메일이 순차적으로 발송된다.
현재 각 이메일이 개별 Order 카드로 생성되어 칸반 Inbox에 중복 표시되며, 담당자는 동일 건을 반복 처리해야 한다.
이 기능은 동일 이벤트 번호의 카드를 **1개 메인 카드로 자동 병합**하고, 이후 수신되는 이메일은 해당 카드에 스레드로 추가하여 중복 카드를 제거한다.

### 1.2 Background

- `Order#reference_no` 컬럼 및 인덱스 이미 존재 (스키마 확인)
- `by_reference_no` 스코프 이미 구현됨
- 기존 `kanban-inbox-grouping` 계획(뷰 레이어 그룹핑)의 **근본 해결책** — DB 레벨 병합으로 중복 카드 자체를 없앰
- `gmail_thread_id`가 각각 달라서 Gmail 스레드 묶기 불가 → 이벤트 번호 기반 병합 필요

### 1.3 Related Documents

- 기존 계획: `docs/01-plan/features/kanban-inbox-grouping.plan.md`
- Order 모델: `app/models/order.rb`
- Email 동기화: `app/jobs/email_sync_job.rb`

---

## 2. 유저 스토리

### US-01: 기존 중복 카드 병합
**As** 구매팀 담당자,
**I want** 동일 이벤트 번호(reference_no)의 기존 중복 Order 카드들을 1개로 병합하고,
**So that** Inbox 컬럼에서 실제 신규 건만 파악하고 중복 처리를 방지할 수 있다.

**Acceptance Criteria:**
- [ ] 관리자가 "카드 병합 실행" 버튼을 누르면 동일 `reference_no`의 카드 중 가장 오래된 것(또는 최신)을 메인으로 지정
- [ ] 나머지 서브 카드들은 `parent_order_id`를 설정하여 연결 (삭제하지 않음)
- [ ] 병합 후 칸반 Inbox에는 메인 카드 1개만 표시, 서브 카드 수 배지(예: "+2") 노출

### US-02: 신규 이메일 자동 추가
**As** 시스템,
**I want** 새 이메일 수신 시 이벤트 번호가 기존 Order와 일치하면 새 Order 카드를 생성하지 않고 기존 메인 카드에 히스토리를 추가하고,
**So that** 이후 수신되는 이벤트 업데이트 이메일이 자동으로 기존 카드에 누적된다.

**Acceptance Criteria:**
- [ ] `EmailSyncJob`에서 `reference_no` 추출 후 기존 Order 조회
- [ ] 기존 Order 존재 시 새 Order 생성 대신 `Activity` 레코드 추가 + `Comment` 자동 등록
- [ ] 새 Order 미생성 확인 (중복 카드 없음)

### US-03: 서브 이벤트 히스토리 조회
**As** 구매팀 담당자,
**I want** 메인 Order 드로어에서 병합된 모든 서브 이벤트의 이메일 내용과 수신 시각을 확인하고,
**So that** 이벤트 변경 이력을 드로어 한 곳에서 파악할 수 있다.

**Acceptance Criteria:**
- [ ] Order 드로어 "스레드" 탭에 서브 이벤트 목록 표시 (수신 시각, 제목, 본문 요약)
- [ ] 서브 이벤트는 시간순 정렬
- [ ] 서브 이벤트 클릭 시 원본 이메일 내용 확인 가능

---

## 3. Scope

### 3.1 In Scope

- [ ] `Order` 모델에 `parent_order_id` 컬럼 추가 (self-referential)
- [ ] `reference_no` 추출 로직: `original_email_subject`에서 8자리 이상 숫자 패턴 파싱
- [ ] `EmailSyncJob` 수정: 신규 이메일 수신 시 기존 Order 존재 여부 확인 후 분기
- [ ] 병합 실행 Admin 액션 (기존 중복 카드 일괄 처리)
- [ ] 칸반 Inbox 뷰: 서브 카드 제외, 메인 카드에 서브 수 배지 표시
- [ ] Order 드로어 스레드 탭: 서브 이벤트 목록 (Hotwire Turbo Frame)
- [ ] `Activity` 자동 기록: "이벤트 업데이트 수신"

### 3.2 Out of Scope

- Gmail 스레드 ID 기반 병합 (thread ID가 이미 각각 달라서 불가)
- reviewing 이후 컬럼에서의 병합 처리
- 수동 카드 병합 UI (관리자 스크립트로 대체)
- 병합된 카드의 개별 상태 관리 (메인 카드 상태가 대표)
- AI 기반 유사 이벤트 감지 (이벤트 번호 완전 일치만)

---

## 4. 데이터 모델 변경

### 4.1 신규 컬럼

```ruby
# migration: add_parent_order_id_to_orders
add_column :orders, :parent_order_id, :integer, null: true
add_index  :orders, :parent_order_id
add_foreign_key :orders, :orders, column: :parent_order_id
```

### 4.2 Order 모델 연관

```ruby
belongs_to :parent_order, class_name: "Order", optional: true
has_many   :sub_orders,   class_name: "Order", foreign_key: :parent_order_id, dependent: :nullify
```

### 4.3 reference_no 추출 정규식

```ruby
# 8자리 이상 숫자 추출 (ARIBA 이벤트 번호 패턴)
ARIBA_EVENT_PATTERN = /\b(\d{8,})\b/

def self.extract_event_number(subject)
  subject&.match(ARIBA_EVENT_PATTERN)&.[](1)
end
```

### 4.4 기존 데이터 영향

| 상태 | 처리 방식 |
|------|---------|
| `parent_order_id: nil` | 독립 카드 (기존과 동일) |
| `parent_order_id: N` | 서브 카드 — 칸반에서 숨김 |
| `reference_no` 있는 메인 카드 | sub_orders 수 배지 표시 |

---

## 5. 요구사항

### 5.1 기능 요구사항 (MoSCoW)

| ID | 요구사항 | 우선순위 |
|----|---------|---------|
| FR-01 | `parent_order_id` 컬럼 추가 및 self-referential 연관 설정 | Must |
| FR-02 | `reference_no` 자동 추출 (`original_email_subject` 파싱) | Must |
| FR-03 | `EmailSyncJob` 분기: 기존 Order 있으면 Activity만 추가 | Must |
| FR-04 | 칸반 Inbox 뷰: 서브 카드 필터링 + 메인 카드 배지 | Must |
| FR-05 | Order 드로어 스레드 탭: 서브 이벤트 히스토리 | Must |
| FR-06 | Admin 일괄 병합 스크립트 (기존 중복 데이터 정리) | Must |
| FR-07 | 병합 Activity 자동 로그 ("이벤트 업데이트 수신") | Should |
| FR-08 | 칸반 컬럼 카운트: 서브 카드 제외 기준 | Should |
| FR-09 | 서브 이벤트 원본 이메일 본문 표시 | Could |
| FR-10 | 이벤트 번호로 Order 검색 필터 | Could |

### 5.2 비기능 요구사항

| 항목 | 기준 |
|------|------|
| 칸반 로딩 성능 | 서브 카드 제외 쿼리 추가 후 200ms 이내 유지 |
| 데이터 안전성 | 서브 카드 삭제 없음 — `parent_order_id` 참조만 변경 |
| 하위 호환성 | `parent_order_id: nil` 카드는 기존과 동일하게 동작 |

---

## 6. 구현 우선순위

```
1단계 (DB + 모델): parent_order_id 마이그레이션 + Order 연관 추가
   └─ FR-01, FR-02
2단계 (Job 수정): EmailSyncJob 분기 로직
   └─ FR-03
3단계 (기존 데이터 정리): Admin 병합 스크립트 실행
   └─ FR-06
4단계 (칸반 뷰): 서브 카드 숨김 + 배지
   └─ FR-04, FR-08
5단계 (드로어 스레드 탭): Hotwire Turbo Frame
   └─ FR-05, FR-07
```

---

## 7. 성공 지표

- [ ] Inbox 컬럼에서 동일 이벤트 번호 카드가 1개만 표시됨
- [ ] 신규 이벤트 업데이트 이메일 수신 시 새 카드 미생성 확인
- [ ] 드로어 스레드 탭에서 전체 이벤트 이력 조회 가능
- [ ] 기존 중복 카드(약 30~50건 예상) 데이터 손실 없이 병합 완료

---

## 8. 리스크

| 리스크 | 영향 | 대응 |
|--------|------|------|
| reference_no 미설정 기존 카드 존재 | 병합 누락 | 병합 전 `reference_no` null 건 별도 검토 |
| 이벤트 번호 패턴 오탐 (8자리 숫자가 다른 의미) | 잘못된 병합 | 병합 전 관리자 검토 단계 추가 |
| 서브 카드 기반 업무가 진행 중인 경우 | 데이터 혼란 | `parent_order_id` 설정만, 삭제 없음 |

---

## 9. 다음 단계

1. [ ] Design 문서 작성 (`card-merge.design.md`) — DB 마이그레이션 + Job 시퀀스 다이어그램
2. [ ] 기존 `kanban-inbox-grouping` 계획과 통합 여부 결정 (이 계획으로 대체 권장)
3. [ ] CTO 승인 후 구현 착수

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-03-03 | Initial draft | PM Agent |
