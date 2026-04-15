# eCount OAPI 검증 신청 명세서

**신청 회사**: AtoZ2010 (COM_CODE: 148829)
**신청자**: K_KDS (CEO)
**신청일**: 2026-04-15
**응용 시스템**: CPOFlow (사내 조달·발주 관리 SaaS)
**연동 목적**: 발주 업무의 중복 입력 제거 — eCount ERP를 단일 진실 원천(SSOT)으로 유지하면서, CPOFlow에서 품목/재고/거래처 마스터를 조회하여 구매 요청서(RFQ) 처리 및 발주서 생성에 활용

---

## 1. 시스템 개요

### 1-1. CPOFlow 아키텍처
- **스택**: Ruby on Rails 8.1, SQLite3, Solid Queue
- **배포**: Vultr 단일 서버 (운영 서버 1대, IP: `158.247.235.31`)
- **개발**: 로컬 1대 (IP: `61.74.179.84`)
- **사용자**: AtoZ2010 조달팀 5명 (CEO + 매니저 1 + 멤버 3)

### 1-2. 연동 IP 등록 완료
- `158.247.235.31` (Vultr 운영서버)
- `61.74.179.84` (개발·테스트용)

### 1-3. 호출 빈도 예측
| 시나리오 | 빈도 | 비고 |
|---|---|---|
| 품목/거래처 마스터 동기화 | **1회/일** (새벽 3시 배치) | 페이지당 50건 × sleep 3s |
| 실시간 재고 조회 | 사용자 주문 상세 진입 시 | 품목당 10분 캐시 |
| 전체 API 호출 예상 | **일 평균 500건 이내** | eCount 레이트 리밋(60/min)의 **1% 미만** |

---

## 2. 신청 메뉴 — 우선순위별

### 2-1. [1순위] `ViewBasicInfo` — 품목 기초정보 조회

**용도**: CPOFlow `Product` 테이블과 eCount 품목 마스터 동기화 (ecount_code 키 기반 upsert)

**샘플 요청**:
```http
POST /OAPI/V2/InventoryBasic/ViewBasicInfo?SESSION_ID=<session>
Content-Type: application/json

{
  "PROD_CD": "",
  "PAGE_COND": { "PAGE_SIZE": 50, "PAGE_NUM": 1 }
}
```

**기대 응답 필드**:
- `PROD_CD` (품목코드) — CPOFlow ecount_code로 매핑
- `PROD_DES` (품목명)
- `SIZE_DES` (규격)
- `UNIT` (단위)
- `CLASS_CD` (분류코드)
- `PRICE` (단가)
- `CURR_CD` (통화)
- `USE_YN` (사용여부)

**호출 패턴**:
- 일 1회 배치, 페이지당 50건 페이징
- 페이지 간 `sleep(3초)` 강제
- 총 예상 요청 수: 품목 마스터 총건수 ÷ 50 (예: 3000건이면 60 request)

---

### 2-2. [1순위] `ViewInventoryStatus` — 재고현황 조회

**용도**: CPOFlow 주문 상세 화면에서 실시간 재고 표시 (CSV 업로드 대체)

**샘플 요청**:
```http
POST /OAPI/V2/InventoryStatus/ViewInventoryStatus?SESSION_ID=<session>
Content-Type: application/json

{
  "PROD_CD": "A001-XX-001",
  "BASE_DATE": "20260415"
}
```

**기대 응답 필드**:
- `PROD_CD` (품목코드)
- `CURR_QTY` (현재 재고량)
- `WH_CD` (창고코드)
- `BASE_DATE` (기준일)

**호출 패턴**:
- 사용자가 주문 상세 진입 시 on-demand
- **Rails.cache 10분 TTL** — 동일 품목 반복 조회 방지
- 일 예상 호출: 50~100회 (활성 사용자 수 × 평균 조회 빈도)

---

### 2-3. [2순위] `ViewCust` — 거래처 기초정보 조회

**용도**: CPOFlow `Client`/`Supplier` 테이블과 eCount 거래처 마스터 동기화

**샘플 요청**:
```http
POST /OAPI/V2/CustomerBasic/ViewCust?SESSION_ID=<session>
Content-Type: application/json

{
  "CUST_CD": "",
  "PAGE_COND": { "PAGE_SIZE": 50, "PAGE_NUM": 1 }
}
```

**호출 패턴**: 품목과 동일 (일 1회 배치)

---

### 2-4. [3순위 — 후순위 신청] `SaveSlipP` — 구매전표 등록

**용도**: CPOFlow에서 승인된 발주를 eCount로 전송

**샘플 요청**:
```http
POST /OAPI/V2/PurSlip/SaveSlipP?SESSION_ID=<session>
Content-Type: application/json

{
  "SlipList": [
    {
      "BULK_DATAS": {
        "IO_DATE": "20260415",
        "CUST": "V00001",
        "PROD_CD": "A001-XX-001",
        "QTY": "10",
        "PRICE": "25000",
        "REMARKS_WIN": "CPOFlow 자동 생성"
      }
    }
  ]
}
```

**호출 패턴**: 사용자가 발주 승인 버튼 클릭 시 1회 (일 5~20회 예상)

---

## 3. 보안·데이터 보호

### 3-1. 인증키 관리
- `config/credentials.yml.enc` (Rails 표준 암호화 저장소) 사용
- `.env.local` 로컬 개발용 — `.gitignore` 등재 확인 완료
- Git 커밋 시 평문 키 포함 불가 (`gitleaks` 훅 보호)

### 3-2. 세션 캐싱
- `SESSION_ID`는 Rails.cache에 23시간 TTL로 저장 (eCount 세션 유효기간 24h 내)
- 세션 만료 감지 시 자동 재발급 (무한 루프 방지를 위한 1회 재시도 제한)

### 3-3. 레이트 리밋 준수
- 코드 내 `MAX_RETRIES = 3`, 지수 백오프 `RETRY_DELAYS = [2, 4, 8]`
- `4001` (레이트 리밋) 수신 시 재시도 금지 — 다음 주기까지 대기
- 페이지 간 `sleep(3초)` — 60req/min 한도의 1/3 수준

### 3-4. 데이터 최소화 원칙
- 필요한 필드만 저장 (CPOFlow DB에 eCount 민감 정보 미동기화)
- 개인정보성 필드(거래처 연락처 등)는 필요 시에만 조회, 저장 시 Lockbox 암호화

---

## 4. 모니터링·감사

### 4-1. 호출 로그
- 모든 eCount API 호출은 `Rails.logger.info`에 기록
- 실패 호출은 `Rails.logger.warn` + `Activity` 테이블에 이벤트 저장

### 4-2. 동기화 추적
- `EcountSyncLog` 테이블에 일자별 동기화 결과 보관
- 컬럼: `total_count`, `success_count`, `error_count`, `started_at`, `finished_at`

### 4-3. 알림
- 배치 실패 3회 연속 시 관리자 이메일 + Google Chat 알림

---

## 5. 기계적 크롤링 방지 조치

본 시스템은 다음과 같이 설계되어 **기계적 크롤링이 아닌 정식 애플리케이션 연동** 임을 밝힙니다:

1. **단일 엔트리포인트**: 모든 호출이 `EcountApi::BaseService`를 경유 — 분산 병렬 호출 불가
2. **User-Agent 명시**: `CPOFlow/1.0 (AtoZ2010 Inc., Ruby on Rails 8.1)`
3. **예측 가능한 호출 패턴**: 일 1회 배치 + 사용자 명시적 액션만 트리거
4. **중복 호출 차단**: Rails.cache 기반 (품목 24h, 재고 10분)
5. **전체 데이터 덤프 없음**: 사용 기능(품목·재고·거래처)만 수집, 전표 이력/회계 데이터는 미요청
6. **권한 분리**: API 호출 주체는 K_KDS(CEO) 단일 계정, 인증키 1개로 제한

---

## 6. 검증 요청 연락처

- **기술 문의**: socialdoctors35@gmail.com (대표 강승식)
- **회사 공식 메일**: ceo@atozone.com (필요 시)

---

## 부록: 엔드포인트 경로 확인 요청

현재 테스트 인증키로 다음 경로를 호출했으나 전부 "Not Found" 응답입니다:
- `/OAPI/V2/InventoryBasic/ViewBasicInfo`
- `/OAPI/V2/Inventory/BasicInfo/GetBasicInfoList`
- `/OAPI/V2/OAPIView/ViewBasicInfo`

검증 승인 시 **정확한 엔드포인트 경로 + 요청 스펙 문서 URL**을 함께 전달받기를 요청드립니다. eCount API 매뉴얼 포털(https://apihelp.ecount.com/ 또는 유사)이 있다면 접근 권한을 함께 발급 부탁드립니다.

---

**본 문서는 eCount OAPI 검증 신청서에 첨부용으로 준비되었으며, 승인 후 실제 구현은 코드 리뷰 가능한 형태로 git 저장소에 공개됩니다.**
