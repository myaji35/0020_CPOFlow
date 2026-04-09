# FEATURE PLAN: recall-safety (ISS-047)

> **Version**: 1.1 (v1.0 CEO+Eng Review 반영)
> **Status**: READY_FOR_IMPLEMENTATION (Phase A 단독 착수 가능, Phase B~E는 ISS-045와 조율)
> **Author**: product-manager (harness)
> **Created**: 2026-04-09
> **Parent**: ISS-047
> **Related**: ISS-045 (email-classify-v2 v1.1), ISS-050 (SQLite hotfix ✅)

---

## Revision Log

| Version | 변경 | Trigger |
|---|---|---|
| 1.0 | 초안 (DLQ + Confidence Threshold + Audit Trail) | product-manager |
| **1.1** | 본 revision | CEO APPROVE_WITH_CHANGES (87점) + Eng NEEDS_REVISION (62점) + 코드 실측 |

### v1.1 핵심 변경 (CEO 8건 + Eng Critical 3건 + Must-Fix 7건 반영)

1. 🚨 **confidence 필드는 String label 유지** (Float 전환 비용 회피): 임계값 규칙을 `hybrid_score 30~69 && confidence_label != "high"` 기반으로 재정의
2. 🚨 **EmailSyncJob rescue 지점 신설** (기존 2개 → 5개): parse/detect/create_order/attachment/ariba_queue 각각 begin/rescue/next 블록 추가
3. 🚨 **email_classifications = ISS-045 classification_logs 통합 단일 테이블** (중복 폐기): ISS-045 v1.1 Plan 기반으로 단일 `email_classifications` 테이블만 운영
4. **Phase A 단독 선행 배포** (ISS-045와 독립)
5. **Phase B~E는 ISS-035 eCount API 이후** (CEO 기회비용 지적 반영)
6. **alert 채널**: Slack → **Google Chat webhook** (ISS-036 BLOCKED 우회, 기존 DueNotificationJob 패턴 복제)
7. **DLQ raw_payload 보존**: 180일 → **30일** (용량 축소)
8. **rfq_status enum rfq_uncertain(4) 추가 + uncertain_reason 컬럼** (기존 의미 충돌 방지)
9. **PII 암호화**: `Lockbox encrypts :raw_payload, :reasoning` 명시
10. **KANBAN_VISIBLE_RFQ_STATUSES / inbox scope 회귀** 명시
11. **DlqRetryJob kill switch**: `ENV["CPOFLOW_DLQ_ENABLED"]` 추가
12. **예상 일정**: 12~14일 → **18~20일** 현실화 (선결 3.5일 + Phase A~E)

---

## 1. Overview

### Context
2026-03 KEPCO 이메일 누락 사고 재발 방지. 현재 EmailSyncJob은 message 루프 내부에 rescue가 없어 parse/detect/create_order/attachment 중 하나라도 실패하면 **이후 메시지 전체가 중단되고 mark_synced!도 호출되지 않음** (Eng Review 실측).

### Goals (측정 가능)
- **DLQ coverage 100%** — API/파싱/DB 실패 메일 0건 유실
- **DLQ 자동 복구율 ≥ 85%** — 지수 백오프 6단계로 처리
- **FN rate ≤ 1%** — Confidence Threshold UX로 담당자 개입
- **Audit 쿼리 p95 < 100ms** — 인덱스 설계 명시
- **Uncertain 처리 leadtime < 4h (영업시간)**

### Non-goals
LLM 프롬프트 튜닝(ISS-045), 통계 대시보드 확장(후속 이슈), Gmail API quota 최적화.

---

## 2. 🚨 Eng Critical 3건 대응 (v1.1 핵심)

### Critical 1: confidence 필드 타입 불일치

**실측**: `app/services/gmail/rfq_detector_service.rb:402` — `confidence_label(score)` 메서드가 String(`"high"/"medium"/"low"/"none"`) 반환.

**해결**: Float 전환 **하지 않는다**. 대신 임계값 규칙을 String 기반으로 재정의:

```ruby
# 변경 전 (Plan v1.0):
#   confidence < 0.85 → rfq_uncertain  ← 실행 불가

# 변경 후 (Plan v1.1):
def determine_rfq_status(detection_result)
  case [detection_result[:verdict], detection_result[:confidence]]
  in [:confirmed, "high"]             then :rfq_pending    # 자동 확정
  in [:confirmed, "medium"]            then :rfq_uncertain  # 담당자 확인 필요
  in [:confirmed, "low" | "none"]      then :rfq_uncertain  # 담당자 확인 필요
  in [:uncertain, _]                   then :rfq_uncertain
  in [:excluded, _]                    then :rfq_excluded
  end
end
```

**효과**: 마이그레이션/백필 0건, 기존 LLM 프롬프트 변경 0건. Phase B 예상 2~3일 유지 가능.

### Critical 2: EmailSyncJob rescue 지점 신설

**실측**: `app/jobs/email_sync_job.rb` — rescue는 line 23(최상위), line 77(detect) **2개뿐**. parse/create_order/attachment/ariba_queue는 rescue되지 않음.

**해결**: message 루프 내부를 begin/rescue/next 블록 5개로 재구성.

```ruby
# app/jobs/email_sync_job.rb (v1.1 구조)
messages.each do |msg|
  gmail_message_id = msg.id || msg["id"]

  # Stage 1: parse
  parsed = begin
    svc.parse_message(msg)
  rescue => e
    Dlq::Recorder.record(gmail_message_id: gmail_message_id, stage: :parse,
                          error: e, raw_payload: msg.to_h, email_account: account)
    next
  end
  next unless parsed

  # Stage 2: detect (기존 rescue 유지 + DLQ 기록 추가)
  detection = begin
    Gmail::RfqDetectorService.new(parsed).detect
  rescue => e
    Dlq::Recorder.record(gmail_message_id: gmail_message_id, stage: :detect,
                          error: e, raw_payload: parsed, email_account: account)
    next
  end

  # Stage 3: create_order (rescue 신설)
  order = begin
    Gmail::EmailToOrderService.new(parsed, detection, account).create_order!
  rescue => e
    Dlq::Recorder.record(gmail_message_id: gmail_message_id, stage: :create_order,
                          error: e, raw_payload: parsed, email_account: account)
    next
  end
  next unless order

  # Stage 4: attachment (rescue 신설, 부분 실패 허용)
  begin
    Gmail::EmailAttachmentExtractorService.new(order, msg, svc).extract!
  rescue => e
    Dlq::Recorder.record(gmail_message_id: gmail_message_id, stage: :attachment,
                          error: e, raw_payload: nil, email_account: account,
                          resolved_order: order)  # order는 살리되 첨부는 DLQ
  end

  # Stage 5: ariba_queue (rescue 신설)
  begin
    AribaFetchJob.perform_later(order_id: order.id) if ariba_link?(parsed)
  rescue => e
    Dlq::Recorder.record(gmail_message_id: gmail_message_id, stage: :ariba_queue,
                          error: e, email_account: account, resolved_order: order)
  end
end
```

**중요**: DLQ 기록은 **트랜잭션 밖**에서 수행 (롤백되어도 기록 남도록).

### Critical 3: email_classifications = classification_logs 단일 테이블 통합

**합의 (v1.1 확정)**: ISS-045 Plan v1.1에서 정의한 `classification_logs` 테이블을 **폐기**하고, ISS-047 `email_classifications`를 **정사본**으로 사용한다. Shadow Mode 기간에도 이 단일 테이블만 운영.

**ISS-045와의 조율**:
- ISS-045 Phase C (Shadow Mode orchestrator)는 `email_classifications.classifier_version` 컬럼에 `"v1"` / `"v2"` 를 기록
- v1/v2 비교는 `WHERE gmail_message_id = ? GROUP BY classifier_version` 쿼리로 해결
- ISS-045 Plan v1.1 섹션 4.4의 `classification_logs` 참조는 전부 `email_classifications` 로 rename 필요 (ISS-049 작업 종료 후 메모리 노트로 추가)

**효과**: Phase E(통합 + 백필) 4일 → 1일로 단축. 총 일정 3일 절약.

---

## 3. 신규 테이블 설계 (v1.1 최종)

### 3.1 email_dlq

```ruby
create_table :email_dlq do |t|
  t.string   :gmail_message_id, null: false
  t.references :email_account, null: false, foreign_key: true
  t.text     :raw_payload          # Lockbox encrypted
  t.string   :stage, null: false   # parse/detect/create_order/attachment/ariba_queue
  t.string   :error_class, null: false
  t.text     :error_message
  t.text     :error_backtrace      # 첫 10줄
  t.integer  :retry_count, null: false, default: 0
  t.datetime :next_retry_at
  t.datetime :last_attempted_at
  t.string   :status, null: false, default: 'pending'
  t.references :resolved_order, foreign_key: { to_table: :orders }, optional: true
  t.string   :resolved_by
  t.text     :resolution_note
  t.datetime :resolved_at
  t.timestamps

  t.index :gmail_message_id, unique: true
  t.index [:status, :next_retry_at]
  t.index [:email_account_id, :status]
end
```

**Lockbox 암호화**:
```ruby
class EmailDlq < ApplicationRecord
  has_encrypted :raw_payload  # lockbox 이미 운영 중 패턴
end
```

**보존 정책**: 30일 (PruneEmailDlqJob 일 1회).

### 3.2 email_classifications (ISS-045 통합 버전)

```ruby
create_table :email_classifications do |t|
  t.references :order, foreign_key: true  # nullable
  t.string   :gmail_message_id, null: false
  t.integer  :email_account_id
  t.string   :classifier_version, null: false  # "v1" | "v2"
  t.string   :model, null: false               # "rule-only" | "haiku-4.5" | "sonnet-4.5"
  t.string   :prompt_version, null: false
  t.string   :stage, null: false               # "stage_1_rule" | "stage_2_haiku" | "stage_3_sonnet"
  t.string   :confidence_label                 # "high"/"medium"/"low"/"none" (v1 호환)
  t.float    :confidence_score                 # 0.0~1.0 (v2에서 사용, v1은 nil)
  t.boolean  :is_rfq, null: false
  t.string   :verdict, null: false             # "confirmed" | "uncertain" | "excluded"
  t.integer  :hybrid_score
  t.text     :reasoning                        # Lockbox encrypted
  t.decimal  :cost_usd, precision: 8, scale: 5
  t.integer  :latency_ms
  t.string   :error_class
  t.text     :error_message
  t.text     :metadata                          # JSON serialized (SQLite 호환)
  t.datetime :classified_at, null: false
  t.timestamps

  # v1.1 인덱스 (최소 + 카디널리티 고려)
  t.index :gmail_message_id                     # 검색 기본
  t.index [:order_id, :classified_at]           # 드로어 히스토리
  t.index [:classifier_version, :classified_at] # v1/v2 비교 (ISS-045)
  t.index :classified_at                        # 보존 정리
end

class EmailClassification < ApplicationRecord
  belongs_to :order, optional: true
  has_encrypted :reasoning
  serialize :metadata, JSON
end
```

**보존 정책**: 180일 (PruneEmailClassificationsJob 일 1회, 가장 최근 1건은 order 살아있는 한 영구 보존).

---

## 4. Order 모델 변경

### 4.1 rfq_status enum 확장

```ruby
# db/migrate/YYYYMMDD_add_uncertain_to_rfq_status.rb
# MEMORY.md 확인: 기존 enum은 rfq_triage(0), rfq_pending(1), rfq_excluded(2), rfq_archived(3)
class AddUncertainToRfqStatus < ActiveRecord::Migration[8.1]
  def up
    # enum 값 4 추가는 코드 레벨에서만 (DB 컬럼은 integer 유지)
    # 별도 컬럼: uncertain_reason
    add_column :orders, :uncertain_reason, :integer
    add_index :orders, :uncertain_reason
  end
  def down
    # rollback 시 uncertain(4) 데이터를 pending(1)로 되돌림
    execute "UPDATE orders SET rfq_status = 1 WHERE rfq_status = 4"
    remove_column :orders, :uncertain_reason
  end
end
```

```ruby
# app/models/order.rb
enum :rfq_status, {
  rfq_triage:    0,
  rfq_pending:   1,
  rfq_excluded:  2,
  rfq_archived:  3,
  rfq_uncertain: 4    # NEW
}, default: :rfq_pending, prefix: :rfq

enum :uncertain_reason, {
  classification_ambiguous: 0,   # hybrid_score 30~69 (기존 의미)
  low_llm_confidence:       1    # LLM confidence medium/low/none (신규)
}, prefix: :uncertain
```

### 4.2 Scope 회귀 (Must-Fix #5)

```ruby
# app/models/order.rb
scope :inbox_pending,  -> { where(rfq_status: [:rfq_pending]) }
scope :inbox_uncertain,-> { where(rfq_status: [:rfq_uncertain]) }  # NEW
scope :inbox_excluded, -> { where(rfq_status: [:rfq_excluded]) }
scope :inbox_triaged,  -> { where(rfq_status: [:rfq_triage]) }

# 칸반 new_rfq 컬럼 가시성 결정:
# rfq_uncertain은 칸반에 표시하지 않는다 (인박스 "AI 확신 낮음" 탭에서만 처리)
KANBAN_VISIBLE_RFQ_STATUSES = [:rfq_triage, :rfq_pending].freeze
```

---

## 5. DLQ 재시도 정책 매트릭스 (Must-Fix #1)

| Stage | Error Class | Max Retry | Backoff Schedule | Permanent 조건 |
|---|---|---|---|---|
| parse | `StandardError` | 3 | 1m→5m→30m | 3회 실패 시 |
| detect | `Faraday::TimeoutError` | 6 | 1m→5m→30m→2h→12h→48h | 6회 실패 또는 API key invalid |
| detect | `Anthropic::RateLimitError` | ∞ | 10m fixed | 24h 이상 누적 시 |
| create_order | `ActiveRecord::RecordInvalid` | 3 | 1m→5m→30m | validation 오류는 즉시 permanent |
| create_order | `SQLite3::BusyException` | 6 | 5s→30s→1m→5m→30m→2h | 6회 |
| attachment | any | 3 | 5m→30m→2h | 3회 (부분 실패) |
| ariba_queue | any | 3 | 1m→5m→30m | 3회 |

**특수 케이스**:
- Gmail 401 (auth) → 즉시 `permanent_failure` + 계정 admin 알림
- Gmail 429 (quota) → exponential with jitter, max 1h

---

## 6. User Stories (7개, v1.1 조정)

| ID | 제목 | 변경 | 의존성 |
|---|---|---|---|
| US-047-1 | Gmail 타임아웃 DLQ 자동 복구 | rescue 신설 강조 | 없음 (Phase A) |
| US-047-2 | DB 에러 DLQ 복구 | 재시도 정책 매트릭스 참조 | Phase A |
| US-047-3 | Inbox "AI 확신 낮음" 탭 + 벌크 확정/제외 | confidence String 기반 판정 | Phase B |
| US-047-4 | Order 드로어 "분류 히스토리" 섹션 | ↓ 우선순위 (Phase D 후반) | Phase C |
| US-047-5 | Admin `/admin/dlq` — 영구실패 수동 해결 + 재시도 + KPI 카드 | KPI 카드 4개 추가 | Phase D |
| US-047-6 | Shadow Mode와 공존 (단일 테이블) | **ISS-045와 단일 테이블 합의** | Phase C |
| US-047-7 | 일일 DLQ 리포트 + **Google Chat webhook** 알림 | Slack → Google Chat 치환 | Phase D |

---

## 7. Phase (v1.1 일정)

| Phase | 내용 | 실측 기간 | 조건 |
|---|---|---|---|
| **선결** | confidence 타입 결정 + rescue 구조 설계서 + ISS-045 테이블 합의 + DLQ 정책 매트릭스 + Google Chat 템플릿 + Lockbox 패턴 확인 + WebMock 인프라 | **3.5일** | 블로커 해소 |
| **Phase A** | DLQ 테이블 + Recorder + RetryService + DlqRetryJob + recurring.yml + EmailSyncJob rescue 5개 신설 + kill switch + Lockbox + 회귀 테스트 | **4~5일** | 독립, **이번 주 착수** |
| **Phase B** | rfq_uncertain enum + uncertain_reason + scope 회귀 + Inbox UI 탭 + Stimulus 벌크 액션 + Turbo Stream + Capybara | **5~6일** | **ISS-035 eCount API 이후** |
| **Phase C** | email_classifications (단일 테이블) + Recorder 훅 + RfqDetectorService/LlmRfqAnalyzerService 통합 | **3~4일** | ISS-045 Phase B 이후 |
| **Phase D** | Admin /admin/dlq + KPI 카드 4개 + 드로어 히스토리 + 180일 파기 Job | **2~3일** | Phase A,C 이후 |
| **Phase E** | ISS-045 cutover 시 classifier_version="v2" 표기 + 운영 Runbook | **1일** | ISS-045 Phase F 이후 |

**총 선결 3.5일 + 실행 15~19일 = 18.5~22.5일** (v1.0 추정 12~14일 대비 +50%)

---

## 8. Success Metrics (v1.1)

| Metric | 목표 | 측정 |
|---|---|---|
| FN rate | ≤ 1% | 월간 수기 검증 샘플 200건 |
| DLQ coverage | 100% | EmailSyncJob 에러 로그 vs email_dlq insert 매칭 |
| 자동 복구율 | ≥ 85% | resolved / 총 DLQ |
| Audit p95 | < 100ms | `order.classifications.order(classified_at: :desc).limit(50)` 벤치 |
| Uncertain leadtime | < 4h 영업시간 | `rfq_uncertain → rfq_pending/excluded` 중앙값 |

---

## 9. Risks & Mitigation (v1.1)

| R | Risk | Mitigation |
|---|---|---|
| R1 | EmailSyncJob rescue 추가로 기존 에러 전파 변경 | 회귀 테스트 최우선, Phase A 테스트 커버리지 > 90% |
| R2 | confidence String 기반 판정이 v2 Float confidence와 호환 불가 | `confidence_label` + `confidence_score` 둘 다 저장, 판정은 hybrid 규칙 |
| R3 | rfq_uncertain enum 추가가 기존 scope 깜박 | KANBAN_VISIBLE/inbox 4개 scope 전수 감사 + Capybara 회귀 |
| R4 | DLQ raw_payload로 DB 용량 폭증 | 30일 자동 파기 + Lockbox 암호화 + resolved 7일 후 payload NULL |
| R5 | email_classifications 14만 row 쿼리 느림 | 인덱스 4개로 최소화, p95 실측 후 추가 |
| R6 | ISS-045 단일 테이블 합의 미이행 | **Plan v1.1에 명시 = 즉시 확정**, ISS-045 Plan v1.2 불필요 (단순 노트만) |
| R7 | Google Chat webhook 미존재 | `DueNotificationJob` 패턴 확인 후 복제, 없으면 Phase A에서 신설 |
| R8 | Confidence 임계값 String 기반이 너무 보수적 | Phase B 배포 2주 후 실측, 규칙 재조정 (코드 변경 1줄) |

---

## 10. CEO 확정 답변 (v1.0 Open Questions 제거)

| Q | 답변 |
|---|---|
| Confidence 임계값 | String 기반 `confidence == "high"` → 자동, 나머지 → uncertain. 2주 후 튜닝 |
| DLQ 재시도 6단계 | 유지. 48h 경과 permanent 시 Google Chat 알림 |
| Audit 보존 기간 | 180일 |
| Shadow Mode 병존 | 최소 2주, 최대 6주 |
| permanent_failure 권한 | admin role만, 해결 사유 필수 |

---

## 11. Definition of Ready
- [x] CEO APPROVE_WITH_CHANGES 8건 반영
- [x] Eng NEEDS_REVISION Critical 3건 반영
- [x] Eng Must-Fix 7건 반영
- [x] ISS-050 SQLite hotfix 완료
- [x] 실측 검증: `confidence_label` String, rescue 지점 2개 확인
- [ ] ISS-035 eCount API 1주 스프린트 (Phase B 전)

---

## 12. 착수 순서 (CEO 권장)

1. **이번 주**: Phase A (DLQ 선행 배포) — 독립 가능
2. **다음 주**: ISS-035 eCount API 스프린트
3. **그 다음**: Phase B (Confidence UX) — ISS-045 Phase B 완료 이후
4. **병렬**: Phase C (Audit Core) — ISS-045 Phase C와 단일 테이블 공유
5. **마무리**: Phase D (Admin) + Phase E (cutover)

---

**Verdict**: READY_FOR_IMPLEMENTATION (Phase A 즉시, 나머지는 CEO 순서)
**Next**: ISS-051 FIX_BUG — EmailSyncJob rescue 5개 신설 + Phase A spawn
