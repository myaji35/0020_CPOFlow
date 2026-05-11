# 품목 탭 + 첨부파일 분석 배지 — Design Spec

- **작성일**: 2026-05-11
- **작성자**: Claude Code (대표님 컨펌 후 작성)
- **대상**: CPOFlow Order Drawer
- **상태**: APPROVED — 구현 계획(`writing-plans`)으로 이동 가능
- **선행 컨펌**: 옵션 C (기존 추출 결과 + 인라인 편집 오버레이)

---

## 1. 목적

발주(Order) 드로어에 **품목(Items) 탭**을 신설하여, 첨부된 견적성 문서(RFQ/QUO/MULKIYA 등)에서 추출한 품목 정보를 RFQ 양식과 동일한 7컬럼 표로 시각화한다.

추가로 첨부파일 항목 옆에 **분석 상태 배지**(`분석` / `견적 분석중...` / `견적분석` / `재분석` / `잔액 부족`)를 표시하여 사용자가 분석 진행 상황을 즉시 파악할 수 있게 한다.

기존 `RfqAuto::*` 파이프라인 자산은 **재사용하지 않는다**. 이 기능은 독립된 모델/잡/서비스 체인으로 구현한다.

---

## 2. 요구사항 매트릭스

| # | 요구사항 | 결정 |
|---|---|---|
| R1 | 드로어 탭바 7번째 "품목" 탭 추가 | 확정 |
| R2 | 첨부파일 항목 옆 분석 상태 배지 | 확정 |
| R3 | 견적성 첨부 자동 판별(휴리스틱) → 분석 버튼 활성화 | 확정 |
| R4 | 품목 탭 = Image #2 RFQ 양식 7컬럼 표 | 확정 |
| R5 | LLM 추출 + 인라인 편집 오버레이 (옵션 C) | 확정 |
| R6 | LLM 모델 = Claude Sonnet 4.6 | 확정 |
| R7 | 분석 트리거 = 사용자 [분석] 버튼 클릭 (자동 큐잉 없음) | 확정 |
| R8 | 사용자 편집 후 재분석 → 편집 보존 + 새 결과 모달 별도 제시 | 확정 |
| R9 | 표시 범위 = 모든 견적성 첨부 합산 (출처 표시) | 확정 |

---

## 3. 데이터 모델

### 3.1 신규 테이블 — `attachment_quote_analyses`
첨부파일 1개당 분석 1회 단위로 상태와 결과를 보관.

| 컬럼 | 타입 | 비고 |
|---|---|---|
| id | bigint | PK |
| order_id | bigint | FK orders.id, NOT NULL |
| active_storage_attachment_id | bigint | FK active_storage_attachments.id, NOT NULL |
| status | string | `pending` / `running` / `completed` / `failed` / `not_quote` |
| is_quote_doc | boolean | LLM 결과 기반 판별 (default: false) |
| items_json | text | LLM이 반환한 품목 배열 JSON (스키마는 §4.4 참조) |
| llm_model | string | "claude-sonnet-4-6" 등 |
| cost_usd | decimal(10,4) | 호출 비용 |
| latency_ms | integer | 분석 소요 시간 |
| error_message | text | 실패 시 사유 |
| reanalyzed_count | integer | 재분석 횟수 (default: 0) |
| started_at | datetime | |
| completed_at | datetime | |
| created_at, updated_at | datetime | |

**인덱스**:
- unique [active_storage_attachment_id] — 첨부 1개당 최신 분석 1건 유지 (재분석은 업데이트, `reanalyzed_count` 증가)
- [order_id, status]

> 결정: 재분석 시 같은 레코드를 업데이트하고 `reanalyzed_count`를 증가. 이전 결과는 손실되지만 `order_quote_items`로 이미 시드된 행은 사용자 편집과 함께 보존되므로 정보 손실은 제한적.

### 3.2 신규 테이블 — `order_quote_items`
사용자에게 보여지는/편집 가능한 최종 품목 행. 분석 결과 시드 + 사용자 편집 오버레이 통합.

| 컬럼 | 타입 | 비고 |
|---|---|---|
| id | bigint | PK |
| order_id | bigint | FK orders.id, NOT NULL |
| source_attachment_id | bigint | FK active_storage_attachments.id, NULL 가능(수동 추가 시) |
| row_no | integer | 1-based 표시 순번 |
| item | string | 품명 (Image #2 "Item") |
| description | text | 사양 멀티라인 (Image #2 "Description") |
| model_part_no | string | Image #2 "Model / Part No" |
| manufacturer_brand | string | Image #2 "Manufacturer / Brand" |
| unit | string | Image #2 "Unit" |
| qty | decimal(12,3) | Image #2 "Qty" |
| remarks | text | Image #2 "Remarks" |
| user_edited | boolean | 사용자가 1번이라도 셀 편집했는지 (default: false) |
| edited_by_user_id | bigint | FK users.id, NULL 가능 |
| created_at, updated_at | datetime | |

**인덱스**:
- [order_id, row_no]
- [source_attachment_id]

### 3.3 모델 관계
```
Order
  has_many :attachment_quote_analyses, dependent: :destroy
  has_many :quote_items, class_name: "OrderQuoteItem", dependent: :destroy

ActiveStorage::Attachment (Rails 표준)
  has_one :quote_analysis, class_name: "AttachmentQuoteAnalysis",
          foreign_key: :active_storage_attachment_id, dependent: :destroy

AttachmentQuoteAnalysis
  belongs_to :order
  belongs_to :attachment, class_name: "ActiveStorage::Attachment",
             foreign_key: :active_storage_attachment_id

OrderQuoteItem
  belongs_to :order
  belongs_to :source_attachment, class_name: "ActiveStorage::Attachment", optional: true
  belongs_to :edited_by_user, class_name: "User", optional: true
```

---

## 4. 서비스/잡 구성

### 4.1 `QuoteAttachmentClassifier` (서비스)
- 입력: `ActiveStorage::Attachment`
- 출력: `:quote_candidate` / `:not_quote` / `:ambiguous`
- 휴리스틱:
  - 양성 키워드 (파일명, 대소문자 무시): `RFQ`, `QUO`, `QUOTE`, `QUOTATION`, `INQUIRY`, `BOQ`, `MULKIYA`, `MTR`
  - 음성 키워드: `INVOICE`, `RECEIPT`, `CONTRACT`, `NDA`, `LICENSE`, `AGREEMENT`
  - 양성 MIME: `application/pdf`, `image/png`, `image/jpeg`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
  - 음성 MIME: `text/calendar`, `application/zip`, `audio/*`, `video/*`
- 자동 트리거 안 함 — **버튼 활성/비활성 결정 + 우선 표시 결정용**으로만 사용.

### 4.2 `QuoteItemExtractor` (서비스)
- 입력: `ActiveStorage::Attachment` + `pages_cap` (default: 5)
- 출력: `{items: [...], cost_usd, latency_ms, llm_model, error: nil}`
- 처리:
  1. PDF면 ImageMagick/poppler로 페이지를 PNG로 변환 (≤5페이지)
  2. 이미지면 그대로 사용
  3. XLSX면 roo로 텍스트 추출 후 텍스트 모드로 호출
  4. Claude Sonnet 4.6 vision API 호출 (system prompt §4.4 참조)
  5. JSON 파싱 → `items[]` 반환
- 예외:
  - 401 / `insufficient_quota` → `AnthropicCreditError` 발생 (메모리 규칙대로 사용자에게 충전 요청 보고)
  - 파싱 실패 → `ExtractionError` 발생
  - 빈 배열 응답 → `is_quote_doc = false` 로 기록 (성공으로 간주)

### 4.3 `QuoteAttachmentAnalyzeJob` (Solid Queue)
- 입력: `attachment_quote_analysis_id`
- 처리:
  1. record.update(status: "running", started_at: Time.current)
  2. broadcast Turbo Stream → 첨부 배지 → "분석중"
  3. `QuoteItemExtractor.call`
  4. 성공 시:
     - record.update(status: "completed", is_quote_doc: items.any?, items_json: items.to_json, ...)
     - `OrderQuoteItem` 시드 (사용자 편집된 행은 보존, 충돌 시 §6 정책 따름)
     - broadcast → 배지 → "견적분석" + 품목 탭 갱신
  5. 실패 시:
     - record.update(status: "failed", error_message: e.message)
     - broadcast → 배지 → "재분석"
     - AnthropicCreditError면 별도 배지 → "잔액 부족"

### 4.4 LLM System Prompt (Sonnet 4.6 vision)
```
You extract procurement RFQ line items from images of quotation request documents.
Return ONLY a JSON object with this exact shape:
{
  "items": [
    {
      "item": "...",
      "description": "...",
      "model_part_no": "...",
      "manufacturer_brand": "...",
      "unit": "...",
      "qty": "...",
      "remarks": "..."
    }
  ]
}
Rules:
- "item" is required (item/product name, original language preserved).
- "description" preserves multi-line specs (DIMENSIONS / MATERIAL / CAPACITY / COLOR / etc).
- "model_part_no": model number or part/SKU (e.g. "5004-BK").
- "manufacturer_brand": OEM/maker or brand (e.g. "ENPAC").
- "unit": EA / KG / SET / M / etc.
- "qty": numeric or numeric-with-unit string.
- "remarks": free-form notes (delivery condition, packaging, QC).
- If document is NOT a procurement RFQ/quotation request, return {"items": []}.
- Output JSON only, no commentary.
```

---

## 5. 라우트 + 컨트롤러

### 5.1 라우트
```ruby
resources :orders do
  resources :quote_items, only: %i[index create update destroy], controller: "order_quote_items"
end
resources :attachment_quote_analyses, only: %i[create] do
  member { post :reanalyze }
end
```

생성 path:
| Verb | Path | 액션 |
|---|---|---|
| GET | /orders/:order_id/quote_items | 품목 탭 partial (Turbo Frame) |
| POST | /orders/:order_id/quote_items | 빈 행 추가 |
| PATCH | /orders/:order_id/quote_items/:id | 인라인 편집 저장 |
| DELETE | /orders/:order_id/quote_items/:id | 행 삭제 |
| POST | /attachment_quote_analyses | 분석 트리거 (params: attachment_id) |
| POST | /attachment_quote_analyses/:id/reanalyze | 재분석 |

### 5.2 컨트롤러 액션 표

| 컨트롤러 | 액션 | 응답 |
|---|---|---|
| OrderQuoteItemsController#index | 품목 탭 partial | Turbo Frame |
| OrderQuoteItemsController#create | append | Turbo Stream |
| OrderQuoteItemsController#update | replace 행 | Turbo Stream |
| OrderQuoteItemsController#destroy | remove 행 | Turbo Stream |
| AttachmentQuoteAnalysesController#create | 잡 인큐 + 배지 갱신 | Turbo Stream |
| AttachmentQuoteAnalysesController#reanalyze | 동상 + 충돌 모달 | Turbo Stream |

### 5.3 권한
- viewer: index만 가능 (편집/분석 트리거 불가)
- member 이상: 모든 액션 가능
- 분석 트리거는 같은 Order 접근 권한이 있는 사용자만

---

## 6. 사용자 편집 vs 재분석 충돌 정책

`order_quote_items`는 분석 결과로 1회 시드되며, 이후 사용자 편집은 `user_edited = true`로 표시된다.

재분석 시:
1. 새 분석 결과를 `attachment_quote_analyses.items_json`에 저장
2. 새 결과를 **별도 모달**로 사용자에게 제시:
   ```
   ┌─────────────────────────────────────────┐
   │ 새 분석 결과를 확인하세요                │
   ├─────────────────────────────────────────┤
   │ • 기존 16건 (수정된 항목 4건 포함)       │
   │ • 새 결과 18건 (신규 +2)                 │
   │                                          │
   │ [기존 유지] [새 결과로 교체] [선택 병합]│
   └─────────────────────────────────────────┘
   ```
3. **기본 동작 = 기존 유지** — 사용자가 명시적으로 "교체" 선택해야 덮어쓰기
4. "선택 병합"은 P5 단계 이후 (MVP 미포함)

---

## 7. 화면 구조

### 7.1 드로어 탭바 (7개)
```
┌────────────────────────────────────────────────────────────────────────┐
│ 상세 │ 태스크 │ 코멘트 │ 첨부파일 N │ 품목 N │ 히스토리 │ 플로우     │
└────────────────────────────────────────────────────────────────────────┘
                                          ▲
                                          └─ 새 탭 (배지 = 품목 행 수)
```

### 7.2 첨부파일 탭 — 분석 상태 배지

배지 상태표:
| 상태 (DB) | 라벨 | 색상 | 클릭 동작 |
|---|---|---|---|
| (레코드 없음) + classifier=quote_candidate | `🔍 분석` | 파랑 | 분석 트리거 |
| (레코드 없음) + classifier=not_quote | (배지 없음) | — | — |
| pending | `⏳ 대기중` | 회색 | 비활성 |
| running | `⏳ 견적 분석중...` | 회색 + 펄스 | 비활성 |
| completed + is_quote_doc=true | `✅ 견적분석` | 파랑 (#00A1E0) | 품목 탭으로 점프 |
| completed + is_quote_doc=false | `🚫 견적 아님` | 회색 | 무시 |
| failed (일반 에러) | `⚠️ 재분석` | 빨강 | 재분석 트리거 |
| failed (잔액 부족) | `💳 잔액 부족` | 빨강 | 모달 안내 (충전 요청) |

### 7.3 품목 탭 콘텐츠

- 헤더: `품목 (Items) — 출처: <첨부 파일명> · 분석: <시각> · N건 추출 · [재분석]`
- 표: 7컬럼 (No · Item · Description · Model/Part No · Manufacturer/Brand · Unit · Qty · Remarks)
  - Description은 textarea (멀티라인 보존)
  - 셀 클릭 → 인라인 입력으로 전환 (Stimulus controller)
  - Blur → PATCH로 저장, `user_edited = true` 표시 (셀 우상단 점)
- 푸터: `[+ 품목 추가]` `[📥 엑셀 다운로드]` `[📤 견적서로 내보내기]` (P5+)

### 7.4 빈 상태
```
┌──────────────────────────────────────────────────────┐
│              📋                                       │
│        품목이 아직 없습니다                            │
│                                                        │
│  견적성 첨부파일에서 [분석] 버튼을 눌러 추출하세요.   │
│                                                        │
│       [+ 직접 추가]    [첨부파일 탭으로]              │
└──────────────────────────────────────────────────────┘
```

### 7.5 분석 진행 중 상태 (Turbo Stream broadcast로 자동 갱신)
```
⏳ MULKIYA 29758.pdf (3페이지) 분석 중... 약 30초 소요
```

---

## 8. 트리거 흐름 (수동 버튼 기반)

```
┌─────────────────────────────────────────┐
│ 첨부파일 업로드 (기존 흐름 유지)          │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Classifier.call(attachment)              │
│  → quote_candidate / not_quote /         │
│    ambiguous                             │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 첨부 항목 옆 [🔍 분석] 버튼 표시          │
│ (not_quote만 버튼 숨김)                  │
└────────────────┬────────────────────────┘
                 ↓ 사용자 클릭
┌─────────────────────────────────────────┐
│ POST /attachment_quote_analyses          │
│  → AttachmentQuoteAnalysis 생성 + Job 인큐│
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ QuoteAttachmentAnalyzeJob.perform_now    │
│  status: pending → running               │
│  Turbo Stream broadcast                  │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ QuoteItemExtractor.call                  │
│  → Claude Sonnet 4.6 vision              │
└────────────────┬────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ status: completed                        │
│ items_json 저장                          │
│ OrderQuoteItem 시드                      │
│ Turbo Stream → 배지 + 품목 탭 갱신       │
└─────────────────────────────────────────┘
```

---

## 9. 엣지 케이스 + 처리

| 케이스 | 처리 |
|---|---|
| Anthropic 잔액 부족 (401) | status=failed, error_message에 사유. 배지=`잔액 부족`. 사용자에게 충전 요청 (메모리 규칙) |
| LLM이 빈 배열 반환 | status=completed, is_quote_doc=false, 배지=`견적 아님` |
| PDF 암호화/손상 | status=failed, error_message="PDF 파싱 실패" |
| 5페이지 초과 PDF | 첫 5페이지만 분석 + 배너 노출 (`5/12 페이지만 분석됨`) |
| 동일 첨부 동시 다중 분석 | unique 제약 + `find_or_initialize_by(active_storage_attachment_id:)` |
| 첨부 삭제 | dependent: :destroy. order_quote_items의 source_attachment_id는 NULL (수동 추가로 전환) |
| 사용자 편집 후 재분석 | 새 결과는 attachment_quote_analyses에만 저장 + 모달로 사용자 결정 위임 |
| 한글/영문 혼합 | LLM 프롬프트에 "원문 언어 보존" 명시 |
| Description 매우 긴 경우 | 셀 max-height 200px + `더보기` 토글 |
| Mobile 화면 (드로어 너비 부족) | 가로 스크롤 + sticky 첫 컬럼(No+Item) |

---

## 10. 비용/성능 추정

| 항목 | 값 |
|---|---|
| 모델 | Claude Sonnet 4.6 (vision) |
| 1 PDF (≤3페이지) 분석 비용 | ~$0.020 |
| 5페이지 cap 시 최대 비용 | ~$0.080 |
| 분석 latency | 평균 15~25초 |
| 일일 예상 분석 건수 | 사용자 트리거 기반 (자동 트리거 없음) → ~20건 |
| 일일 예상 비용 | ~$0.40 ~ $1.60 |

> 자동 트리거를 제거함으로써 자동화 대비 토큰 소모 약 30% 절감 예상.

---

## 11. 구현 단계 (Phase 분할)

| Phase | 범위 | 추정 시간 |
|---|---|---|
| **P1** | 마이그레이션 + 모델 + 라우트 + 빈 품목 탭 + 빈 상태 | 2h |
| **P2** | Classifier + Job + Extractor (LLM 호출) + 첨부 배지 | 3h |
| **P3** | 품목 탭 7컬럼 표 렌더 + 출처/시각 헤더 + 분석중 상태 broadcast | 2h |
| **P4** | 인라인 편집 (Stimulus + Turbo Stream) + user_edited 표식 | 2h |
| **P5** | 재분석 + 충돌 모달 + 잔액 부족 처리 | 1.5h |
| **P6** | 캐릭터 저니 검증(Playwright) + 회귀 테스트 | 1h |
| **합계** | | **~11.5h** |

> 엑셀 다운로드/견적서 내보내기는 본 spec 범위 외 (별도 후속 이슈).

---

## 12. 캐릭터 저니 검증 (대표님 메모리 규칙)

구현 완료 후 Playwright 시나리오 (필수):

### Journey: Member (member 역할)
| 스텝 | 행동 | 기대 결과 |
|---|---|---|
| 1 | 로그인 → 칸반 진입 | 칸반 표시 |
| 2 | 견적성 첨부가 있는 Order 카드 클릭 → 드로어 오픈 | 드로어 표시, [품목] 탭 노출 |
| 3 | [첨부파일] 탭 → MULKIYA 29758.pdf 옆 [🔍 분석] 클릭 | 배지 → "견적 분석중..." |
| 4 | (분석 완료 후) 배지 → "견적분석" 변경 | 자동 갱신 (Turbo Stream) |
| 5 | [품목] 탭 클릭 | 7컬럼 표 16행 표시 |
| 6 | "Item" 셀 클릭 → 텍스트 수정 → blur | 셀 갱신 + 우상단 점 표시 (user_edited) |
| 7 | [+ 품목 추가] 클릭 | 빈 행 1개 추가 |
| 8 | [재분석] 클릭 | 기존 유지/교체 모달 표시 |
| 9 | "기존 유지" 선택 | 표 변동 없음 |

각 스텝 스크린샷 `/tmp/quote-items-journey-{N}.png` 저장.

---

## 13. 의존성 + 가드레일

- **freeze 범위**: `app/models`, `app/controllers`, `app/views/orders`, `app/services`, `app/jobs`, `db/migrate`, `config/routes.rb`, `config/locales/*.yml`
- **금지**:
  - 기존 `RfqAuto::*` 모듈 수정 금지 (격리 유지)
  - 기존 `_drawer_attachments.html.erb` 대대적 리팩토링 금지 (배지 영역만 추가)
  - 기존 `Order.attachment_kinds` 메서드 변경 금지
- **공유 자원**:
  - `claude_token_resolver.rb` 재사용 (API 키 조회)
  - 기존 `ATTACHMENT_MAX_SIZE` 상수 유지
  - SLDS + brand-dna.json 토큰 적용

---

## 14. 미해결/Future Work

- 엑셀 다운로드 (P5+, 별도 이슈)
- 견적서로 내보내기 → eCount ERP 연동 (별도 이슈)
- "선택 병합" 충돌 해결 모드 (MVP 후)
- 분석 결과 이력 보존 (현재 reanalyze는 덮어쓰기) — PaperTrail 도입 검토

---

## 15. 승인 기록

- 2026-05-11: 대표님 클라리파잉 4개 항목 응답 → 승인. spec 작성 진행.
- 2026-05-11: spec 문서 commit 후 대표님 검토 → 승인 시 `writing-plans`로 이행.
