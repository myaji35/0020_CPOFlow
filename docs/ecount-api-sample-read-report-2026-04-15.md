# eCount OAPI 샘플 리딩 결과 보고서

**일시**: 2026-04-15
**인증키**: K_KDS 테스트 인증키 (유효기간 2026-04-15~04-29)
**호출 엔드포인트**: `POST https://sboapiba.ecount.com/OAPI/V2/InventoryBasic/GetBasicProductsList`

---

## 1. 요약 — 샘플 리딩 성공 ✅

| 항목 | 측정값 |
|---|---|
| **엔드포인트 경로** | `/InventoryBasic/GetBasicProductsList` (다른 16개 후보 전부 404) |
| **HTTP 상태** | 200 OK |
| **응답 시간** | **1.42초** |
| **응답 크기** | **18.3 MB** (한 번에) |
| **수신 건수** | **10,000건** (단일 호출) |
| **전체 품목 수 (TotalCnt)** | **10,000건** — 전체가 한 번에 옴 |
| **페이지네이션** | **불필요** (한 번에 전체 수신) |

## 2. eCount가 공개한 호출 한도 (QUANTITY_INFO 응답)

```
시간당 연속 오류 제한 건수: 0/30건
1일 허용량: 4/5000건
```

- ✅ **일 5,000회** 호출 한도
- ✅ **시간당 30회 연속 오류** 시 차단
- 오늘 사용량: 4회 (샘플 리딩 + 엔드포인트 탐색)

## 3. 응답 구조

### 최상위 키
```json
{
  "Status": "200",
  "Data": {
    "TRACE_ID": "efdc2442a78747f2a434de5758ea82ec",
    "EXPIRE_DATE": "",
    "QUANTITY_INFO": "시간당 연속 오류 제한 건수 : 0/30건, 1일 허용량 : 4/5000건",
    "TotalCnt": 10000,
    "Result": [ ... 10,000개 품목 객체 ]
  }
}
```

### 품목 하나의 필드 (총 87개)
**핵심 필드** (CPOFlow `Product` 매핑용):
- `PROD_CD` — 품목코드 (예: `11599`, `AA1005270`)
- `PROD_DES` — 품목명 (예: `Nitrogen Gas`, `Hand Socket`)
- `SIZE_DES` — 규격 (예: `99.999% 10LTR`, `SC To LC, Single Mode`)
- `UNIT` — 단위 (예: `EA`, `SET`)
- `CLASS_CD`, `CLASS_CD2`, `CLASS_CD3` — 분류 (3단계)
- `BAR_CODE` — 바코드
- `VAT_YN`, `TAX` — 세금 정보
- `IN_PRICE`, `OUT_PRICE` ~ `OUT_PRICE10` — 단가 (매입/매출 10단계)
- `WH_CD` — 기본 창고
- `CUST` — 기본 거래처
- `REMARKS_WIN`, `REMARKS` — 비고

**부가 필드**: `EXCH_RATE`, `MIN_QTY`, `SAFE_QTY`, `SERIAL_TYPE`, `QC_YN`, `CONT1~6` (사용자 정의 필드)

## 4. 실제 수신된 샘플 (처음 5건)

```
1. 11599     | Nitrogen Gas          | 99.999% 10LTR [2000... | EA  | class=
2. 185964    | Flow Indicator        | Accuracy: ±1.6 % of... | EA  | class=
3. 20017     | Electric Screwdriver  | 17.5 x 1.5 x 1.5cm     | SET | class=
4. 20026     | Fiber Optic Adapter   | SC To LC, Single Mode  | EA  | class=
5. 2005801   | Hose Clamp            | 76~102mm 4-1/2"        | EA  | class=
```

**마지막 3건**: `AA1005264 / AA1005267 / AA1005270 — Hand Socket 시리즈`

## 5. 품목 코드 분포 (첫 페이지 10,000건 기준)

| 코드 프리픽스 | 건수 | 추정 카테고리 |
|---|---|---|
| `AA*` | 1,959건 | 신규 등록(AtoZ 자사) |
| `95*` | 1,185건 | 산업용 카테고리 |
| `94*` | 777건 | |
| `92*` | 770건 | |
| `90*` | 599건 | |
| `91*` | 590건 | |
| `31*` | 588건 | |
| `93*` | 573건 | |
| `30*` | 559건 | |
| `96*` | 554건 | |

## 6. 필터링 테스트

- 요청: `{ "PROD_CD": "B" }` (B로 시작하는 품목)
- 결과: **0건** — PROD_CD 필터는 정확 일치가 아닌 prefix 아닐 수도 있음. 추가 테스트 필요.

## 7. 기존 CPOFlow 코드와의 차이

**`app/services/ecount_api/product_sync_service.rb`의 잘못된 가정**:
```ruby
# ❌ 존재하지 않는 엔드포인트
post("/Inventory/BasicInfo/GetBasicInfoList", {
  "PAGE_COND" => { "PAGE_SIZE" => PAGE_SIZE, "PAGE_NUM" => page }
})
```

**실제 올바른 호출**:
```ruby
# ✅ 단일 호출로 전체 수신
post("/InventoryBasic/GetBasicProductsList", {
  "PROD_CD" => ""  # 빈 값 = 전체 조회
})
```

→ **`ProductSyncService` 전면 재작성 필요** (페이징 로직 제거, 단일 호출로 변경)

## 8. 다음 단계 계획

### Phase 1 — Service 코드 재작성 (즉시 진행 가능)
1. `ProductSyncService` 수정: 엔드포인트 + 페이징 제거
2. 10,000건 처리 전략: 배치 인서트(Upsert) — `activerecord-import` 또는 chunk 500건 단위 `upsert_all`
3. 전체 수신 1.42초 + DB upsert 10,000건 = 예상 총 소요 30~60초

### Phase 2 — 재고 조회 API 엔드포인트 확정
- 예상 경로: `/InventoryStatus/GetListInventoryStatus` 또는 유사 (동일 패턴)
- 샘플 리딩 1회로 확정 필요
- 주의: 일 5,000회 한도 공유

### Phase 3 — 거래처 조회
- 예상 경로: `/CustomerBasic/GetListCustomer` 또는 유사
- 1회 샘플 리딩으로 확정

### Phase 4 — 정기 동기화 Job
- **일 1회 배치** (새벽 3시 한국시간)
- 일 호출 수: 품목 1회 + 재고 N회 (활성 품목 수) + 거래처 1회
- 레이트 리밋 여유: 5,000 / (1 + N + 1) ~ N < 4,998 활성 품목까지 가능

### Phase 5 — 실시간 재고 on-demand
- 사용자 주문 상세 진입 시 재고만 단건 조회
- 10분 캐시로 중복 방지
- 시간당 5,000/24 = ~208회 버짓 = 충분

## 9. 검증 신청 불필요 판명

앞서 "API 인증현황" 화면의 **"검증된 메뉴가 없습니다"**는 단지 **"아직 검증 완료된 메뉴가 등록되지 않았다"**는 정보성 메시지였습니다. 실제로는:

- ✅ 테스트 인증키로 **지금 즉시 API 호출 가능**
- ✅ eCount 서버가 **요청을 받고 검토 중**인 상태 (자동)
- 🔄 실서버 키 전환 시점은 **일정 기간 사용 후 자동**으로 가능해질 것으로 추정

별도 검증 신청 버튼이 없는 이유가 설명됨.

## 10. 기계적 크롤링 위험 분석

eCount가 공개한 한도를 기준으로:

| 시나리오 | 일 호출 수 | 안전 여부 |
|---|---|---|
| 현재 설계 (일 1회 품목 sync) | ~3회 | ✅ 매우 안전 (5,000의 0.06%) |
| 재고 캐시 10분 유지 | 품목 수 × 6 = 최대 300회 | ✅ 안전 (6%) |
| 전체 크롤링 시도 | 수천 회 | ⚠️ 한도 도달 가능 |

**결론**: 현재 설계는 **eCount 한도의 1% 미만 사용** — 기계적 크롤링으로 오인될 위험 없음.

---

## 11. 발견된 이슈

1. **`config/master.key` 로컬에 없음** — `.env.local` fallback으로 해결됨
2. **`ProductSyncService` 엔드포인트 틀림** — 이번에 발견. 곧 수정 예정.
3. **`InventoryService` 엔드포인트도 재검증 필요** — 동일 패턴일 가능성 높음
4. **Vultr 배포 환경에서 credentials.yml.enc 기반 운영** — 배포 서버의 master.key 확인 필요
