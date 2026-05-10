# LAB/RFQ Auto 재설계 — Anthropic Web Search 제거 + AtoZ RFQ 양식 적용

- **작성일**: 2026-05-10
- **이슈**: ISS-358 (P0, IN_PROGRESS)
- **대표님 지시**: "거래처 찾는 기능은 삭제하고, 파악된 품목을 이미지 양식과 같이 구현하자" (2026-05-09)
- **양식 레퍼런스**: `~/Downloads/KakaoTalk_Photo_2026-05-09-16-57-03.png` (AtoZ Request For Quotation)

---

## 1. 목적

LAB/RFQ Auto가 RFQ PDF/이미지를 분석한 뒤 **Anthropic Claude의 Web Search Tool**로 인터넷에서 공급사를 찾는 기능을 제거. 동시에 분석된 품목을 표시/출력할 때 **AtoZ 자체 RFQ 양식**(7컬럼 표 + Mike Lee 서명 푸터)을 사용하도록 일원화.

## 2. 비목표

- ❌ datago(공공조달 data.go.kr), Google CSE 검색 제거 (대표님 결정: 인터넷 리서치는 Anthropic web_search만 제거)
- ❌ 자체 Supplier DB(local_db) 변경
- ❌ 4단계/5단계 펼침 패널 구조 변경 (recent commit 4531dae)
- ❌ Vision Hybrid 분석 흐름 변경 (b3271ed)
- ❌ Phase 2-A/B (NAWAH/ENEC, Korea BMT) 패턴 라이브러리 영향 없음
- ❌ 기존 발주 PDF 출력은 별도 wkhtmltopdf 경로 유지

## 3. 핵심 결정 (3가지)

### 결정 1 — 제거 범위: Anthropic Web Search Tool만

| 제거 대상 | 유지 대상 |
|---|---|
| `app/services/rfq_auto/web_supplier_finder.rb` (전체 파일) | `supplier_finder.rb` (datago/google_cse/local_db 부분) |
| `SupplierFinder#search_web` 메서드 | `SupplierFinder#search_local`, `search_datago`, `search_google` |
| `WebSupplierFinder` 호출 코드 | 4단계 펼침 패널 + 11항목 매트릭스 |
| 관련 ENV/credentials (`ANTHROPIC_API_KEY` 사용처 한정) | Anthropic credentials 자체는 다른 기능에서 사용 (분석 LLM 등) — 보존 |
| UI에서 "Web Search" 표기 / 비용 / citation 노출 | datago/google_cse citation 노출 |

`SupplierFinder` 자체는 살리되, `enable_web` 옵션을 제거하고 `search_web` 호출 자체를 삭제. `web_cost_usd`, `web_model`, `web_citations`, `web_error` 인스턴스 변수도 제거 (외부 호출자가 의존하는지 확인 후).

### 결정 2 — 양식 적용 범위: 이메일 본문 + 분석 결과 화면

| 영역 | 양식 적용 |
|---|---|
| **RFQ 발송 이메일 (rfq_inquiry.html.erb)** | ✅ AtoZ RFQ 양식 그대로 (헤더/표/푸터/워터마크) |
| **분석 결과 화면 (lab/rfq_auto/show.html.erb 품목표 영역)** | ✅ 동일 양식 (7컬럼 표) — 화면 미리보기 |
| **PDF 출력 (있다면 wkhtmltopdf)** | ✅ 동일 양식 — Phase 1 |
| **칸반 카드 / 드로어 / 발주 폼** | ❌ 영향 없음 (별도 시스템) |

### 결정 3 — RFQ 양식 7컬럼 구조

| 컬럼 | 데이터 소스 | 비고 |
|---|---|---|
| **No.** | 자동 (1, 2, 3...) | |
| **Material Description** | `item[:description]` 또는 `item[:name] + spec` 멀티라인 | 불릿/번호로 사양 나열 (DIMENSION/COLOR/MATERIAL/MODEL 등) |
| **Model / Part No.** | `item[:model]` 또는 `item[:part_no]` | |
| **Manufacturer / Brand Name** | `item[:manufacturer]` 또는 `item[:brand]` | 분석 미식별 시 빈칸 |
| **Unit** | `item[:unit]` (e.g., EA, BOX, m, m²) | |
| **Qty** | `item[:quantity]` | |
| **Remarks** | `item[:remarks]` 또는 빈칸 | |

Item 모델 또는 hash가 위 키들을 다 가지고 있는지 사전 점검 필요. 누락 키는 빈 칸 또는 "—" 표시.

---

## 4. 양식 디테일 (AtoZ RFQ 레이아웃)

### 4.1 헤더
```
                    Request For Quotation

RFQ No.       : <%= @order.rfq_no %>
Inquiry Due Date  : <%= @inquiry_due_date %>
Inquiry Address   : Sector M41 - Abu Dhabi Industrial City - ICAD I - Abu Dhabi PO Box 93543
                    (또는 client.country 따라 동적)

Please provide the best quotation for the below inquiry.
Note: Please include the delivery charge to this address.
```

### 4.2 표
- 회색 헤더 배경 (`#E5E5E5`)
- 1px 검정 테두리
- 좌측 정렬 본문, Material Description은 멀티라인 허용
- Qty/Unit 우측 정렬

### 4.3 푸터
```
If you have further clarifications, please do not hesitate to contact us.

Thank you.
Best regards,
Mike Lee   ← 또는 current_user 분기 (결정 1)

Email: sales@atoz2010.com
+971 2 553 5580

       [AtoZ 로고]
A TO Z SUPPLY CHAIN TRADING LLC
Email: sales@atoz2010.com / +971 2 553 5580 / Musaffah, Abu Dhabi, UAE
```

### 4.4 발신자 정보 (Mike Lee 부분)

**옵션 A**: 하드코딩 "Mike Lee" + sales@atoz2010.com
**옵션 B**: `current_user.display_name` + `current_user.email` (동적)
**옵션 C**: Order의 assigned_user 기준

권장: **B (동적, current_user)** — 발신자 책임 추적 + 회신 라우팅. Mike Lee는 historical default.

---

## 5. 영향 파일

### 5.1 제거
- `app/services/rfq_auto/web_supplier_finder.rb` — 전체 삭제
- `test/services/rfq_auto/web_supplier_finder_test.rb` (있다면) — 삭제

### 5.2 수정 (제거 코드 정리)
- `app/services/rfq_auto/supplier_finder.rb`:
  - `search_web` 메서드 제거
  - `enable_web` 파라미터 제거
  - `web_cost_usd` / `web_model` / `web_citations` / `web_error` 인스턴스 변수 + 접근자 제거
  - `auto_save_high_confidence` 메서드는 유지 (datago/google_cse도 신뢰도 기반 자동 저장 가능)
- `app/services/rfq_auto/analyzer.rb`:
  - `enable_web` 또는 `WebSupplierFinder` 직접 호출 부분 제거 (있는 경우)
- `app/views/lab/rfq_auto/show.html.erb`:
  - 품목 표 영역을 AtoZ RFQ 양식으로 교체
  - "Web Search" / "Anthropic" 라벨/비용/citation 노출 제거
- `app/views/lab/rfq_auto/_analysis_card.html.erb`:
  - WebSupplierFinder citation 표시 제거
- `app/controllers/lab/rfq_auto_controller.rb`:
  - `enable_web` 파라미터/세션 키 제거 (있는 경우)
- `app/views/rfq_auto_mailer/rfq_inquiry.html.erb`:
  - 기존 표 구조를 AtoZ 7컬럼 양식으로 교체
  - 헤더 + 푸터 추가 (RFQ No., Due Date, Address, Mike Lee or current_user)
- `app/views/rfq_auto_mailer/rfq_inquiry.text.erb`:
  - 텍스트 버전도 양식 일치하게 갱신

### 5.3 신규 (옵션)
- `app/views/shared/_atoz_rfq_letterhead.html.erb` — 헤더 partial (재사용)
- `app/views/shared/_atoz_rfq_footer.html.erb` — 푸터 partial (재사용)
- AtoZ 로고 이미지 자산 (있다면 그대로, 없으면 텍스트로 대체)

### 5.4 i18n
- 양식이 영어 고정 (대표님 지시: "Request For Quotation"은 영어 표준 양식)
- 한국어 번역 불필요 — 단, 분석 결과 화면의 메타 라벨(품목명, 수량 등)은 dev 한국어 / prod 영어 분기 유지

---

## 6. 환경 변수 / Credentials 정리

`WebSupplierFinder` 제거 시 영향:
- `ENV["ANTHROPIC_API_KEY"]` — **다른 기능에서 사용 중**(GraphRAG, 분석 LLM 등) → 그대로 유지
- `ENV["ANTHROPIC_WEB_SEARCH_ENABLED"]` 또는 유사 플래그 — 제거
- `Rails.application.credentials.dig(:anthropic, :web_search_*)` — 사용 흔적 검색 후 제거

검색 명령:
```bash
grep -rn "web_search\|WebSupplierFinder\|enable_web" app/ config/ --include="*.rb" --include="*.erb"
```

---

## 7. Wave 분할

| Wave | 범위 | 예상 작업 |
|---|---|---|
| **Wave 1 (제거)** | T1: web_supplier_finder.rb 삭제 / T2: supplier_finder.rb 정리 (search_web, enable_web 제거) / T3: analyzer.rb 호출 경로 정리 / T4: 컨트롤러+뷰의 web_search 라벨/citation 제거 | 4 commits |
| **Wave 2 (양식 적용 - 이메일)** | T5: AtoZ RFQ 양식 partial(letterhead, footer) 신규 / T6: rfq_inquiry.html.erb 7컬럼 양식 적용 / T7: rfq_inquiry.text.erb 양식 일치 | 3 commits |
| **Wave 3 (양식 적용 - 화면)** | T8: lab/rfq_auto/show.html.erb 품목 영역 양식 적용 / T9: _analysis_card.html.erb 정리 | 2 commits |
| **Wave 4 (테스트)** | T10: SupplierFinder 회귀 테스트 / T11: rfq_auto_mailer 양식 렌더 테스트 / T12: lab/rfq_auto controller 회귀 + ENV cleanup verification | 3 commits |

**총 예상**: 12 commits

---

## 8. Risk Register

| # | 리스크 | 완화 |
|---|---|---|
| R1 | `WebSupplierFinder` 호출자가 다른 곳에 있어 제거 시 NoMethodError | grep 사전 검색 + Wave 1 T1 전에 호출 경로 전수 점검 |
| R2 | `auto_save_high_confidence`가 web_supplier 결과에 의존 | datago/google_cse 결과로 전환 시 같은 신뢰도 기준(70+) 적용 — 재테스트 |
| R3 | 양식 변경으로 이메일 수신 거래처 혼란 (양식 갑자기 바뀜) | 기존 양식과 차이 미미 (헤더/푸터만 추가, 표 구조는 유사) — 사전 알림 불필요 |
| R4 | wkhtmltopdf 렌더 시 양식 깨짐 (CSS) | inline style 사용 + Phase 1 검증 |
| R5 | i18n 분기 — 한국어 dev에서 영어 양식 노출 | 양식 자체는 영어 고정(거래처 송부용), 한국어는 미리보기 라벨에만 |
| R6 | 기존 RFQ 분석 사이클 회귀 (4단계 펼침 패널) | Wave 4에서 lab/rfq_auto controller 통합 테스트 |

---

## 9. Done Definition

| Acceptance | 검증 방법 |
|---|---|
| `web_supplier_finder.rb` 파일 부재 | `ls app/services/rfq_auto/web_supplier_finder.rb` → not found |
| `SupplierFinder#search_web` 메서드 부재 | `grep -n "search_web\|enable_web" app/services/rfq_auto/supplier_finder.rb` → 0건 |
| Anthropic web_search 호출 흔적 0건 | `grep -rn "WebSupplierFinder\|web_search.*tool" app/` → 0건 |
| RFQ 발송 이메일이 AtoZ 양식 | manual: 테스트 발송 후 수신 확인 |
| 분석 결과 화면 품목표가 AtoZ 양식 | system test 또는 ApplicationController.renderer 검증 |
| RFQ Auto 4단계 펼침 패널 회귀 0건 | 기존 controller test 통과 |
| Anthropic credentials 다른 기능에서 정상 작동 | 분석 LLM (analyzer.rb) 회귀 테스트 통과 |

---

## 10. 단축 사이클 (Phase 2와 동일 패턴)

이슈 자체가 비교적 명확하므로:
- spec → eng-review BLOCKER 점검 → 4 wave 구현
- plan 별도 문서 생략 (spec §7 Wave 분할이 plan 역할 겸함)
- Phase 1/2와 동일하게 agent-harness wave 단위 spawn
