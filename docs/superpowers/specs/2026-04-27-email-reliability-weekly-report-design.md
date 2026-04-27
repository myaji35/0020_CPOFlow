# 받음편지함 신뢰도 주간 레포트 (Email Reliability Weekly Report) 설계

**작성일**: 2026-04-27
**작성자**: Claude (with 강승식 대표)
**상태**: Approved (브레인스토밍 완료, 구현 계획 작성 대기)
**관련 이슈**: 신규 — `EMAIL_RELIABILITY_REPORT_V1`

---

## 1. 목적

CPOFlow 받음편지함이 Gmail 원장에 도착한 견적성(RFQ) 메일을 **얼마나 정확하게 캐치하고 있는가**, 그리고 정상 수신된 메일의 **첨부파일이 얼마나 온전히 처리되고 있는가**를 주차별로 정량화·시각화한다.

지금까지 운영 측면에서 막연히 "견적 메일이 가끔 누락된다"는 체감만 있었고, 특히 대표님이 지적한 **"docx 첨부파일이 자주 누락된다"** 는 가설을 정량으로 증명·진단할 수단이 없었다. 본 보고서는 이를 두 층(Layer)의 신뢰도 KPI로 분리해서 측정한다.

- **Layer 1 — 수신 신뢰도**: 받음편지함이 Gmail 원장의 견적성 메일을 몇 % 캐치했나
- **Layer 2 — 첨부 신뢰도**: 정상 수신된 견적성 메일의 첨부파일이 4단계 처리 파이프라인을 몇 % 통과했나

## 2. 분모/분자 정의

### 2.1 Layer 1 — 수신 신뢰도

| 항목 | 정의 |
|---|---|
| **분자** | DB의 `rfq_status IN (rfq_confirmed, rfq_uncertain)` 메일 중 해당 주차에 수신된 건수 |
| **분모** | Gmail 원장(Search API)에서 휴리스틱으로 후보를 추출한 뒤, 받음편지함과 **동일한** `RfqDetectorService`로 재판정하여 견적성으로 판정된 총 건수 |
| **수식** | `L1 신뢰도 = 분자 / 분모` |

**핵심 원칙**: 분자와 분모가 같은 LLM 잣대로 판정되어야 % 의 의미가 있다. 키워드 휴리스틱만으로 분모를 산출하면 단위가 어긋난다.

### 2.2 Layer 2 — 첨부 신뢰도

대표님이 강조한 **"받음편지함에 정상적으로 들어왔지만 첨부파일이 누락된 케이스"** 를 가시화한다. 4단계 처리 파이프라인을 정의한다.

| 단계 | 정의 | 측정 컬럼 |
|---|---|---|
| ① **다운로드** | Gmail API에서 attachment payload(바이너리) 수신 성공 | `downloaded_at` |
| ② **저장** | ActiveStorage 또는 로컬 파일로 영속화 | `stored_at` |
| ③ **파싱** | 확장자별 파서로 본문 텍스트 추출 성공 (`parsed_text` 길이 > 0) | `parsed_at`, `parsed_text_length` |
| ④ **LLM 투입** | 추출된 텍스트가 `RfqDetectorService` 입력에 실제로 포함됨 | `included_in_llm_at` |

**Layer 2 KPI 3종**:

| 지표 | 분자 | 분모 |
|---|---|---|
| **L2-메일 신뢰도** | 첨부 4단계 모두 통과한 견적성 메일 수 | 첨부 1개 이상 있는 견적성 메일 수 |
| **L2-파일 신뢰도** | 4단계 모두 통과한 첨부파일 수 | 견적성 메일에 딸린 첨부파일 총 수 |
| **L2-확장자별 신뢰도** | (위와 동일하되 확장자 분리) | 동일 |

**확장자 카테고리**: `.docx / .xlsx / .pdf / .zip / .eml / image(.png/.jpg/.gif) / other`

## 3. 컴포넌트 설계 (책임 분리)

각 컴포넌트는 독립 호출·테스트 가능. 책임 경계를 명확히 분리한다.

### 3.1 `EmailReliability::LedgerScanner`

**책임**: 주차 단위로 Gmail 원장에서 견적성 후보를 추출하고 동일 LLM으로 재판정하여 분모를 산출한다.

```ruby
EmailReliability::LedgerScanner.call(week_iso: "2026-W14", email_account: account)
# => {
#   ledger_total: 540,                       # 해당 주차 메일함 전체
#   ledger_rfq_count: 200,                   # 견적성으로 판정된 분모
#   inbox_rfq_count: 184,                    # DB에서 가져온 분자
#   missing_message_ids: [...],              # 분모에는 있는데 분자에는 없는 메일들
#   unscanned_count: 3                       # LLM 호출 실패로 미판정된 후보
# }
```

**의존성**: Gmail API, `RfqDetectorService`, `EmailAccount`

### 3.2 `EmailReliability::AttachmentTracker`

**책임**: 견적성 메일 1건의 첨부파일이 4단계 중 어디까지 통과했는지 검사한다.

```ruby
EmailReliability::AttachmentTracker.call(email_id: 12345)
# => [
#   { ext: "docx", stage1: true, stage2: true, stage3: false, stage4: false, failure_at: 3, file_name: "RFQ_2024_001.docx" },
#   { ext: "pdf",  stage1: true, stage2: true, stage3: true,  stage4: true,  failure_at: nil, file_name: "spec.pdf" }
# ]
```

**의존성**: `AttachmentRecord`(아래 5절 신설), `ClassificationLog`

### 3.3 `EmailReliability::WeeklyReportBuilder`

**책임**: Scanner + Tracker를 조합하여 `EmailReliabilityReport` row 1개를 생성·갱신한다.

```ruby
EmailReliability::WeeklyReportBuilder.call(week_iso: "2026-W14")
# => EmailReliabilityReport (saved)
```

**처리 흐름**:
1. 모든 활성 `EmailAccount`에 대해 LedgerScanner 호출 → L1 분모/분자 합산
2. 해당 주차의 견적성 메일 전수 조회 → AttachmentTracker로 4단계 집계
3. 메일/파일/확장자별/단계별 KPI 산출
4. 누락 샘플 Top 20 추출 (실패 단계 + 메타데이터)
5. `EmailReliabilityReport` upsert (week_iso unique)

### 3.4 `Admin::EmailReliabilityController` + 뷰 + PDF Export

**책임**: 운영자가 주차를 선택해 KPI를 보고 PDF로 내보낸다.

- 라우트: `/admin/email_reliability`
- 파라미터: `?week=2026-W14`
- 액션: `index` (주차 선택 + 렌더), `export_pdf` (wkhtmltopdf 호출)

## 4. UI 설계 (SLDS + brand-dna 토큰)

`/admin/email_reliability?week=2026-W14`

```
┌─ Email Reliability — 2026-W14 (3/30 ~ 4/5) ───────────────────────┐
│  주차: [W14 ▼]                              [PDF 내보내기]         │
├────────────────────────────────────────────────────────────────────┤
│ KPI 카드 3종                                                       │
│ ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│ │ Layer 1     │  │ L2 메일     │  │ L2 파일     │                 │
│ │   92%       │  │   87%       │  │   81%       │                 │
│ │ 184/200     │  │ 145/167     │  │ 312/385     │                 │
│ └─────────────┘  └─────────────┘  └─────────────┘                 │
├────────────────────────────────────────────────────────────────────┤
│ 4단계 처리 깔때기 (Funnel)                                         │
│ ①다운로드 98%  ②저장 97%  ③파싱 82% ⚠  ④LLM 78%                  │
│  [▰▰▰▰▰]    [▰▰▰▰▰]   [▰▰▰▰░]    [▰▰▰▰░]                     │
├────────────────────────────────────────────────────────────────────┤
│ 확장자별 신뢰도                                                    │
│   docx  ▰▰▰░░ 65%  ⚠ 핫스팟                                       │
│   xlsx  ▰▰▰▰▱ 92%                                                 │
│   pdf   ▰▰▰▰▰ 95%                                                 │
│   zip   ▰▰▰▰░ 88%                                                 │
│   eml   ▰▰▰▰▰ 100%                                                │
│   image ▰▰▰▰▰ 99%                                                 │
├────────────────────────────────────────────────────────────────────┤
│ 누락 샘플 Top 20                                                   │
│ ┌───┬─────────┬──────────────┬─────────────────┬──────┬────────┐  │
│ │ # │ msg_id  │ sender       │ subject         │ ext  │ 실패단계│ │
│ │ 1 │ abc123  │ buyer@x.com  │ RFQ 2024-001    │ docx │ ③파싱  │ │
│ │ 2 │ def456  │ proc@y.com   │ Inquiry Q1      │ docx │ ③파싱  │ │
│ │...│         │              │                 │      │        │  │
│ └───┴─────────┴──────────────┴─────────────────┴──────┴────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

**디자인 토큰** (brand-dna.json):
- Hero(KPI 강조): `#166c72`
- Text Primary: `#151a21`
- Surface: `#ffffff`
- Radius: tight (≤12px) — `rounded-md`
- Anti-pattern 회피: 큰 라운드, 투명 배지, 화려한 그라데이션 금지
- Typography: Inter Tight + Pretendard Variable

**상태 신호**:
- KPI ≥ 95%: 녹색
- 80% ≤ KPI < 95%: 주황 ⚠
- KPI < 80%: 빨강 ▲ (즉시 액션 필요)

**Primary CTA per screen**: "PDF 내보내기" 1개 (brand-dna `primary_action_per_screen: MUST_EXIST` 충족).

## 5. 데이터 모델

### 5.1 신규 테이블: `email_reliability_reports`

주차당 1행. 무기한 보관 (주당 1행 → 연간 52행, 용량 부담 없음).

```ruby
create_table :email_reliability_reports do |t|
  t.string  :week_iso, null: false                    # "2026-W14"
  t.date    :week_start, null: false
  t.date    :week_end, null: false

  # Layer 1
  t.integer :layer1_ledger_total, default: 0
  t.integer :layer1_ledger_rfq, default: 0            # 분모
  t.integer :layer1_inbox_rfq, default: 0             # 분자
  t.decimal :layer1_reliability, precision: 5, scale: 4
  t.integer :layer1_unscanned_count, default: 0       # LLM 호출 실패 분리 카운트

  # Layer 2 — 메일 단위
  t.integer :layer2_mail_total, default: 0
  t.integer :layer2_mail_pass, default: 0
  t.decimal :layer2_mail_reliability, precision: 5, scale: 4

  # Layer 2 — 파일 단위
  t.integer :layer2_file_total, default: 0
  t.integer :layer2_file_pass, default: 0
  t.decimal :layer2_file_reliability, precision: 5, scale: 4

  # Breakdown
  t.json    :stage_breakdown                          # {stage1: 0.98, stage2: 0.97, ...}
  t.json    :ext_breakdown                            # {docx: {total: 50, pass: 33, rate: 0.66}, ...}
  t.json    :missing_samples                          # Top 20 누락 메일 메타

  t.datetime :generated_at, null: false
  t.timestamps
end
add_index :email_reliability_reports, :week_iso, unique: true
add_index :email_reliability_reports, :week_start
```

### 5.2 신규/확장 테이블: `attachment_records`

기존에 첨부파일 추적 모델이 부재하면 신설. 이미 일부 필드가 다른 모델(예: `Email` 또는 ActiveStorage)에 있다면 보강한다.

```ruby
create_table :attachment_records do |t|
  t.references :email, null: false, foreign_key: true   # 또는 Order/RfqMail 등 실제 부모
  t.string  :gmail_attachment_id
  t.string  :file_name, null: false
  t.string  :extension                                  # "docx" | "xlsx" | ...
  t.integer :byte_size

  # 4단계 타임스탬프 (null = 미통과)
  t.datetime :downloaded_at        # ① 다운로드
  t.datetime :stored_at            # ② 저장
  t.datetime :parsed_at            # ③ 파싱
  t.datetime :included_in_llm_at   # ④ LLM 투입

  t.integer :parsed_text_length, default: 0
  t.string  :failure_reason                             # 실패 시 메시지
  t.timestamps
end
add_index :attachment_records, :email_id
add_index :attachment_records, :extension
```

기존 첨부 처리 코드(`email_attachment_extractor_service.rb` 등)에 위 4개 타임스탬프를 기록하는 instrumentation을 추가한다.

## 6. 자동화

### 6.1 백필 (4월 1주차 ~ 4월 4주차, 1회성)

```bash
bin/rails runner "EmailReliability::WeeklyReportBuilder.call(week_iso: '2026-W14')"
# 또는 rake task
bundle exec rake email_reliability:backfill[2026-W14,2026-W17]
```

- 주차별 독립 트랜잭션 — 1주차 실패해도 다른 주차 영향 없음
- LLM 호출 비용 추정: Haiku 단가 기준 4주치 후보 메일 수천 건 → **$15 이내** 1회성

### 6.2 주간 자동 집계

Solid Queue cron:

```ruby
# config/recurring.yml 또는 동등 위치
weekly_email_reliability:
  class: EmailReliability::WeeklyReportJob
  schedule: "0 6 * * 1"   # 매주 월요일 06:00 KST (= 21:00 UTC 일요일)
  args: { week_iso: "previous" }   # 직전 주(W-1)
```

`WeeklyReportJob`은 `WeeklyReportBuilder.call`을 위임 호출.

### 6.3 PDF 출력

- 컨트롤러 `format.pdf` 분기에서 `WickedPdf` 또는 직접 `wkhtmltopdf` 호출
- 저장 경로: `tmp/reports/email_reliability_<week>.pdf` 캐시
- 다운로드 시 `~/Downloads/이메일신뢰도_<week>.pdf` 권장 (전역 보고서 규칙)
- SLDS 스타일 + 표지 + 목차 + 푸터 페이지번호 (전역 규칙 준수)

## 7. 에러 처리

| 시나리오 | 대응 |
|---|---|
| Gmail API rate limit | 지수 백오프 (1s, 2s, 4s, 8s), Solid Queue 재큐 |
| LedgerScanner LLM 호출 실패 | 메일당 3회 재시도 후 `unscanned` 마킹, 분모에서 제외하되 `layer1_unscanned_count`로 카운트 노출 |
| 첨부 파싱 실패 (③단계) | `failure_reason` 기록 — Layer 2 분석의 핵심 신호 (수정 대상이 됨) |
| WeeklyReportBuilder 부분 실패 | 주차 단위 트랜잭션, 다른 주차에 영향 X. 실패 시 `EmailReliabilityReport`는 row 미생성 → 다음 실행에서 재시도 |
| 백필 중단 | rake task가 idempotent — 같은 week_iso로 재호출하면 upsert |

## 8. 테스트 전략

| 컴포넌트 | 테스트 종류 | 핵심 검증 |
|---|---|---|
| `LedgerScanner` | 단위 (VCR) | Gmail API + LLM 응답 고정 → 분모 카운트가 정확한가, unscanned 분리되는가 |
| `AttachmentTracker` | 단위 | 4단계 각각의 fixture (성공/실패 조합) → failure_at 정확성 |
| `WeeklyReportBuilder` | 통합 | Scanner/Tracker mock → row 1개 생성 + KPI 계산 정확성 |
| `Admin::EmailReliabilityController` | 시스템 | 주차 선택 → KPI 렌더 → PDF 다운로드 (200 OK + Content-Type) |
| 백필 rake | 수동 검증 | 4주치 백필 후 `EmailReliabilityReport.count == 4` |

목표 커버리지: **신규 코드 ≥ 80%**.

## 9. 보안 / 개인정보

- 누락 샘플의 `subject` / `sender` 는 PII에 해당 가능 — Admin 권한(role: `admin` 또는 `manager`) 사용자만 접근
- PDF 파일은 `tmp/reports/` 임시 저장 후 1시간 내 자동 삭제 (Solid Queue 정리 잡)
- LLM 재판정 시 메일 본문이 외부 API(Anthropic)로 전송됨 — 기존 받음편지함 처리와 동일한 데이터 처리 정책 적용 (이미 합의된 흐름)

## 10. YAGNI 적용 (v1에서 제외)

| 제외 항목 | 이유 | 후속 |
|---|---|---|
| 4주차 비교 차트 | v1은 단순 주차 선택만, 추세는 v2 | v2 이슈 등록 |
| 발신자 도메인별 누락률 | 의미 있으나 v1엔 불필요 | v2 후보 |
| 누락 메일 → FIX_BUG 자동 생성 | 수작업으로 충분, 자동화는 신뢰성 검증 후 | v2 후보 |
| Slack/이메일 알림 push | PDF + 대시보드로 충분 | v3 후보 |
| 사용자별 처리율 | 개인 평가로 오용 위험 | 미정 |

## 11. 구현 단계 요약 (writing-plans 스킬 input용)

1. DB 마이그레이션 — `email_reliability_reports`, `attachment_records` (또는 보강)
2. 기존 첨부 처리 서비스에 4단계 타임스탬프 instrumentation 추가
3. `EmailReliability::LedgerScanner` 구현 + 단위 테스트
4. `EmailReliability::AttachmentTracker` 구현 + 단위 테스트
5. `EmailReliability::WeeklyReportBuilder` 구현 + 통합 테스트
6. 백필 rake task 작성 + W14~W17 1회 실행
7. `Admin::EmailReliabilityController` + 뷰 + Stimulus(주차 선택) + 시스템 테스트
8. PDF export (wkhtmltopdf) + 디자인 토큰 적용
9. Solid Queue cron 등록 (`WeeklyReportJob`)
10. 운영 페이지 메뉴(`/admin`) 진입점 추가

---

## 부록 A. 분모 산출 휴리스틱(Gmail Search 쿼리)

```
( subject:(RFQ OR quotation OR inquiry OR quote OR 견적 OR 문의)
  OR has:attachment filename:(docx OR xlsx OR pdf)
)
after:YYYY/MM/DD before:YYYY/MM/DD
```

위 쿼리로 후보를 추출 → `RfqDetectorService.call(email)`로 재판정 → 견적성으로 판정된 건만 분모에 합산.

## 부록 B. ISO Week 정의

- 월요일 시작, 일요일 종료
- 2026-W14 = 2026-03-30 (월) ~ 2026-04-05 (일)
- 2026-W15 = 2026-04-06 (월) ~ 2026-04-12 (일)
- 2026-W16 = 2026-04-13 (월) ~ 2026-04-19 (일)
- 2026-W17 = 2026-04-20 (월) ~ 2026-04-26 (일)

`Date#cweek`, `Date#cwyear` 사용.
