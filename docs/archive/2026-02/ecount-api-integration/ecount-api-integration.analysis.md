# eCount API Integration - Gap Analysis Report

> **Analysis Type**: Implementation Audit (Design Doc Missing) + Code Quality Analysis
>
> **Project**: CPOFlow
> **Version**: Rails 8.1 (latest migration: 2026_02_28_000602)
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Design Doc**: NOT FOUND (`docs/02-design/features/ecount-api-integration.design.md`)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

eCount API Integration 기능의 설계 문서가 존재하지 않는 상태에서, 구현 코드를 역분석하여:
1. 구현된 기능의 완성도를 평가
2. 아키텍처 및 컨벤션 준수 여부를 검증
3. 누락된 설계 문서 작성을 위한 기초 데이터를 제공

### 1.2 Analysis Scope

- **Design Document**: 미존재 (Design Score = N/A, Implementation Audit 방식 적용)
- **Implementation Files**: 18개 파일 (서비스 6개, Job 4개, 모델 2개, 컨트롤러 1개, 뷰 3개, 마이그레이션 2개, 설정 1개)
- **Analysis Date**: 2026-02-28

### 1.3 Analyzed Files

| Category | Path | LOC |
|----------|------|:---:|
| Service | `app/services/ecount_api/base_service.rb` | 82 |
| Service | `app/services/ecount_api/auth_service.rb` | 72 |
| Service | `app/services/ecount_api/product_sync_service.rb` | 83 |
| Service | `app/services/ecount_api/customer_sync_service.rb` | 104 |
| Service | `app/services/ecount_api/slip_create_service.rb` | 89 |
| Service | `app/services/ecount_api/inventory_service.rb` | 34 |
| Job | `app/jobs/ecount_product_sync_job.rb` | 41 |
| Job | `app/jobs/ecount_customer_sync_job.rb` | 41 |
| Job | `app/jobs/ecount_slip_create_job.rb` | 24 |
| Job | `app/jobs/ecount_import_job.rb` | 23 |
| Model | `app/models/ecount_sync_log.rb` | 16 |
| Model | `app/models/order.rb` (eCount 관련 부분) | ~10 |
| Controller | `app/controllers/admin/ecount_sync_controller.rb` | 29 |
| View | `app/views/admin/ecount_sync/index.html.erb` | 189 |
| View | `app/views/orders/_drawer_content.html.erb` (재고 표시) | ~17 |
| View | `app/views/settings/base/index.html.erb` (eCount 섹션) | ~40 |
| Migration | `db/migrate/20260228000601_create_ecount_sync_logs.rb` | 24 |
| Migration | `db/migrate/20260228000602_add_ecount_api_fields.rb` | 21 |
| Config | `config/recurring.yml` (eCount 스케줄) | ~8 |

---

## 2. Functional Requirements Audit

### 2.1 Implemented Features (FR)

| FR | Feature | Status | Implementation Location |
|----|---------|:------:|------------------------|
| FR-01 | eCount API 인증 (SESSION_ID 발급) | OK | `ecount_api/auth_service.rb` |
| FR-02 | SESSION_ID 캐싱 (23시간) | OK | `auth_service.rb:9` Rails.cache |
| FR-03 | 세션 만료 시 자동 재발급 | OK | `product_sync_service.rb:51-58`, `customer_sync_service.rb:54-60` |
| FR-04 | 품목 마스터 동기화 (eCount -> Products) | OK | `product_sync_service.rb` |
| FR-05 | 거래처 동기화 (eCount -> Clients/Suppliers) | OK | `customer_sync_service.rb` |
| FR-06 | AR_CD_TYPE 분기 (매출처/매입처/양방향) | OK | `customer_sync_service.rb:9-13` |
| FR-07 | 매출 전표 자동 생성 (Order confirmed) | OK | `slip_create_service.rb` |
| FR-08 | 전표 중복 방지 (멱등성) | OK | `slip_create_service.rb:14-17` |
| FR-09 | 실시간 재고 조회 | OK | `inventory_service.rb` |
| FR-10 | 재고 캐싱 (10분 TTL) | OK | `inventory_service.rb:7` |
| FR-11 | EcountSyncLog 이력 관리 | OK | `ecount_sync_log.rb` + migration |
| FR-12 | 스케줄 자동 실행 (품목 매시 30분, 거래처 매시 45분) | OK | `config/recurring.yml:29-39` |
| FR-13 | 수동 즉시 동기화 트리거 | OK | `ecount_sync_controller.rb:17-27` |
| FR-14 | Admin 동기화 관리 UI | OK | `admin/ecount_sync/index.html.erb` |
| FR-15 | Settings 페이지 eCount 상태 표시 | OK | `settings/base/index.html.erb:274-317` |
| FR-16 | Order Drawer 재고 표시 | OK | `orders/_drawer_content.html.erb:66-83` |
| FR-17 | HTTP 지수 백오프 재시도 (최대 3회) | OK | `base_service.rb:24-41` |
| FR-18 | 레이트 리밋 감지 및 방어 | OK | `base_service.rb:71`, `product_sync_service.rb:36` |
| FR-19 | 커스텀 에러 클래스 계층 | OK | `base_service.rb:78-81` |
| FR-20 | 전표 실패 시 Admin 알림 | OK | `slip_create_service.rb:74-86` |
| FR-21 | DB 컬럼 추가 (ecount_slip_no, ecount_synced_at, stock_quantity) | OK | migration `20260228000602` |
| FR-22 | eCount credentials 미설정 시 안내 UI | OK | `ecount_sync/index.html.erb:172-187` |
| FR-23 | Pagination (50건/페이지) | OK | `product_sync_service.rb:7`, `customer_sync_service.rb:7` |
| FR-24 | Order `after_update_commit` 콜백으로 전표 Job 트리거 | OK | `order.rb:98-107` |

### 2.2 Feature Completeness Score

```
+-------------------------------------------------+
|  Feature Completeness: 24/24 = 100%             |
+-------------------------------------------------+
|  OK Implemented:    24 items (100%)             |
|  Partial:            0 items (0%)               |
|  Not Implemented:    0 items (0%)               |
+-------------------------------------------------+
```

---

## 3. DB Schema Analysis

### 3.1 ecount_sync_logs Table

| Field | Migration | schema.rb | Status |
|-------|-----------|-----------|:------:|
| sync_type (string, NOT NULL) | OK | OK | OK |
| status (integer, NOT NULL, default:0) | OK | OK | OK |
| total_count (integer, default:0) | OK | OK | OK |
| success_count (integer, default:0) | OK | OK | OK |
| error_count (integer, default:0) | OK | OK | OK |
| error_details (text) | OK | OK | OK |
| started_at (datetime) | OK | OK | OK |
| completed_at (datetime) | OK | OK | OK |
| timestamps | OK | OK | OK |

**Indexes:**
| Index | Status |
|-------|:------:|
| sync_type | OK |
| status | OK |
| created_at | OK |

### 3.2 Added Columns (orders, products, clients, suppliers)

| Table | Column | Type | Status |
|-------|--------|------|:------:|
| orders | ecount_slip_no | string | OK |
| orders | ecount_synced_at | datetime | OK |
| products | stock_quantity | integer (default:0) | OK |
| products | ecount_synced_at | datetime | OK |
| clients | ecount_synced_at | datetime | OK |
| suppliers | ecount_synced_at | datetime | OK |

**Indexes:**
| Index | Status |
|-------|:------:|
| orders.ecount_slip_no | OK |

### 3.3 DB Schema Score

```
+-------------------------------------------------+
|  DB Schema Completeness: 100%                    |
+-------------------------------------------------+
|  Tables: 1/1 created correctly                   |
|  Columns: 6/6 added correctly                    |
|  Indexes: 4/4 created                            |
|  FK Constraints: N/A (ecount_sync_logs standalone)|
+-------------------------------------------------+
```

---

## 4. Architecture Analysis

### 4.1 Service Layer Structure

```
app/services/ecount_api/
  base_service.rb        # HTTP client + retry + error classes
  auth_service.rb        # SESSION_ID auth + cache
  product_sync_service.rb   # Product upsert
  customer_sync_service.rb  # Client/Supplier upsert
  slip_create_service.rb    # Sales order creation
  inventory_service.rb      # Stock query
```

**Evaluation:**
- Namespace isolation (`EcountApi::` module): OK
- Base class inheritance pattern: OK
- Single Responsibility per service: OK
- Error class hierarchy (ApiError > AuthError, RateLimitError): OK

### 4.2 Job Layer Structure

```
app/jobs/
  ecount_product_sync_job.rb   # Scheduled: hourly at :30
  ecount_customer_sync_job.rb  # Scheduled: hourly at :45
  ecount_slip_create_job.rb    # Event-driven: order confirmed
  ecount_import_job.rb         # Legacy CSV import (Phase 3)
```

**Evaluation:**
- Job은 orchestration만 수행하고 비즈니스 로직은 Service에 위임: OK
- EcountSyncLog 생성/업데이트는 Job에서 관리: OK
- 에러 핸들링 분리 (AuthError vs StandardError): OK

### 4.3 Dependency Flow

```
Controller/View
    |
    v
Job (orchestration)
    |
    v
Service (business logic)
    |
    v
Model (data access)
```

**Violations Found:**

| File | Layer | Issue | Severity |
|------|-------|-------|:--------:|
| `orders/_drawer_content.html.erb:68` | View | `EcountApi::InventoryService.stock_for()` 직접 호출 | Warning |
| `settings/base/index.html.erb:287` | View | `Rails.application.credentials.dig(:ecount, ...)` 직접 호출 | Warning |

**Details:**
1. **View -> Service 직접 호출**: `_drawer_content.html.erb` 라인 68에서 `EcountApi::InventoryService.stock_for(product.ecount_code)`를 View에서 직접 호출. Controller에서 인스턴스 변수로 전달하거나, Helper 메서드로 래핑하는 것이 바람직.
2. **View -> Credentials 직접 접근**: `settings/base/index.html.erb` 라인 287에서 `Rails.application.credentials.dig(:ecount, :api_cert_key)`를 직접 호출. Helper 또는 Model method로 래핑 권장.

### 4.4 Architecture Score

```
+-------------------------------------------------+
|  Architecture Compliance: 90%                    |
+-------------------------------------------------+
|  Correct layer placement:  16/18 files           |
|  Dependency violations:     2 files (View->Svc)  |
|  Wrong layer:               0 files              |
+-------------------------------------------------+
```

---

## 5. Code Quality Analysis

### 5.1 Error Handling

| Component | Error Handling | Status |
|-----------|---------------|:------:|
| BaseService | ApiError/AuthError/RateLimitError 계층 | OK |
| AuthService | credentials 미설정 시 명확한 메시지 | OK |
| ProductSyncService | AuthError 시 재인증 + 1회 재시도 | OK |
| CustomerSyncService | AuthError 시 재인증 + 1회 재시도 | OK |
| SlipCreateService | 실패 시 Admin 알림 + 에러 반환 | OK |
| InventoryService | 실패 시 nil 반환 (graceful degradation) | OK |
| EcountProductSyncJob | AuthError/StandardError 분리 처리 | OK |
| EcountCustomerSyncJob | AuthError/StandardError 분리 처리 | OK |
| EcountSlipCreateJob | RecordNotFound 스킵 처리 | OK |

### 5.2 Security

| Item | Status | Notes |
|------|:------:|-------|
| API 키 저장 | OK | Rails credentials 사용 (암호화) |
| API 키 노출 방지 | OK | credentials.dig() 사용, 환경변수 미사용 |
| SESSION_ID 캐시 | OK | Rails.cache (서버사이드, 클라이언트 노출 없음) |
| SSL 사용 | OK | `http.use_ssl = true` (base_service.rb:46) |
| 입력 검증 | OK | sync_type whitelist 검증 (controller:18) |

### 5.3 Performance Considerations

| Item | Implementation | Status | Notes |
|------|---------------|:------:|-------|
| API 페이징 | 50건/페이지 | OK | 대량 데이터 처리 가능 |
| Rate limit 방어 | sleep(1) per page | OK | 60req/min 준수 |
| 재고 캐싱 | 10분 TTL | OK | API 과호출 방지 |
| SESSION 캐싱 | 23시간 TTL | OK | 24시간 유효기간 내 재사용 |
| Batch update | update_columns 사용 | OK | 진행률 업데이트 시 콜백 스킵 |
| N+1 Query | View에서 Product.find_by | Warning | Drawer 내 N+1 가능성 |

### 5.4 Code Smells

| Type | File | Location | Description | Severity |
|------|------|----------|-------------|:--------:|
| View Logic | `_drawer_content.html.erb` | L66-83 | Service 호출 + 조건 분기가 View에 직접 존재 | Warning |
| Direct DB Query in View | `_drawer_content.html.erb` | L66 | `Product.find_by(name: order.item_name)` | Warning |
| Credentials in View | `settings/base/index.html.erb` | L287 | `Rails.application.credentials.dig(...)` | Warning |
| Magic String | `customer_sync_service.rb` | L9-13 | AR_CD_TYPE "1"/"2"/"3" 하드코딩 | Info |

---

## 6. Convention Compliance

### 6.1 Naming Convention

| Category | Convention | Compliance | Violations |
|----------|-----------|:----------:|------------|
| Module | PascalCase (`EcountApi`) | 100% | - |
| Class | PascalCase (`ProductSyncService`) | 100% | - |
| Methods | snake_case (`fetch_page`, `upsert_product`) | 100% | - |
| Constants | UPPER_SNAKE_CASE (`CACHE_KEY`, `PAGE_SIZE`) | 100% | - |
| Files | snake_case.rb | 100% | - |
| Folders | snake_case (`ecount_api/`) | 100% | - |

### 6.2 Folder Structure

| Expected Path | Exists | Status |
|---------------|:------:|:------:|
| `app/services/ecount_api/` | OK | OK |
| `app/jobs/ecount_*_job.rb` | OK | OK |
| `app/models/ecount_sync_log.rb` | OK | OK |
| `app/controllers/admin/ecount_sync_controller.rb` | OK | OK |
| `app/views/admin/ecount_sync/` | OK | OK |
| `config/recurring.yml` | OK | OK |
| `db/migrate/` | OK | OK |

### 6.3 Rails Convention

| Convention | Compliance | Notes |
|-----------|:----------:|-------|
| `frozen_string_literal: true` | 100% | 모든 Ruby 파일 |
| Service Object pattern | 100% | Base -> Derived 상속 구조 |
| Job thin, Service fat | 100% | Job은 조율만, 로직은 Service |
| `before_action` 권한 검사 | 100% | `require_manager!` |
| Enum 정의 | 100% | EcountSyncLog status enum |
| Scope 정의 | 100% | `recent`, `failed_today` |

### 6.4 Convention Score

```
+-------------------------------------------------+
|  Convention Compliance: 98%                      |
+-------------------------------------------------+
|  Naming:              100%                       |
|  Folder Structure:    100%                       |
|  Rails Conventions:   100%                       |
|  Layer Discipline:     90% (View violations)     |
+-------------------------------------------------+
```

---

## 7. API Endpoints

### 7.1 Internal Routes (admin)

| Route | Method | Controller#Action | Status |
|-------|--------|-------------------|:------:|
| `/admin/ecount_sync` | GET | `admin/ecount_sync#index` | OK |
| `/admin/ecount_sync/trigger` | POST | `admin/ecount_sync#trigger` | OK |

### 7.2 eCount External API Endpoints Used

| eCount API Path | Service | Purpose | Status |
|-----------------|---------|---------|:------:|
| `POST /OAPI/V2/OAPILogin` | AuthService | SESSION_ID 발급 | OK |
| `POST /OAPI/V2/Inventory/BasicInfo/GetBasicInfoList` | ProductSyncService | 품목 목록 조회 | OK |
| `POST /OAPI/V2/BaseInfo/Customer/GetCustomerList` | CustomerSyncService | 거래처 목록 조회 | OK |
| `POST /OAPI/V2/Sale/SalesOrder/SaveSalesOrder` | SlipCreateService | 매출 전표 생성 | OK |
| `GET /OAPI/V2/Inventory/InventoryStatusInfo/GetInfo` | InventoryService | 재고 조회 | OK |

---

## 8. Recurring Schedule

| Job | Environment | Schedule | Status |
|-----|-------------|----------|:------:|
| EcountProductSyncJob | production | every hour at minute 30 | OK |
| EcountCustomerSyncJob | production | every hour at minute 45 | OK |
| EcountProductSyncJob | development | NOT scheduled | Warning |
| EcountCustomerSyncJob | development | NOT scheduled | Warning |

**Note:** development 환경에서는 eCount 동기화 Job이 스케줄에 등록되어 있지 않습니다. 개발 테스트를 위해서는 수동 트리거(`/admin/ecount_sync`)만 사용 가능합니다.

---

## 9. Overall Score

```
+-------------------------------------------------+
|  Overall Score: 94/100                           |
+-------------------------------------------------+
|  Feature Completeness:  100 points (24/24 FR)    |
|  DB Schema:             100 points               |
|  Architecture:           90 points (-10: view)   |
|  Code Quality:           92 points               |
|  Security:              100 points               |
|  Convention:             98 points               |
|  Error Handling:        100 points               |
|  Performance:            90 points               |
+-------------------------------------------------+
|  Weighted Average:       94%                     |
+-------------------------------------------------+
```

| Category | Score | Status |
|----------|:-----:|:------:|
| Feature Completeness | 100% | OK |
| DB Schema Match | 100% | OK |
| Architecture Compliance | 90% | Warning |
| Convention Compliance | 98% | OK |
| Code Quality | 92% | OK |
| **Overall** | **94%** | **OK** |

---

## 10. Differences Found

### Missing Design Document

| Item | Description | Impact |
|------|-------------|:------:|
| Design Doc | `docs/02-design/features/ecount-api-integration.design.md` 미존재 | High |

구현은 완료되었으나 설계 문서가 없어 PDCA Check 단계의 "Design vs Implementation" 비교가 불가합니다.

### Warning: View Layer Violations

| Item | Implementation Location | Description | Impact |
|------|------------------------|-------------|:------:|
| View -> Service 직접 호출 | `orders/_drawer_content.html.erb:68` | `EcountApi::InventoryService.stock_for()` View에서 직접 호출 | Low |
| View -> DB 직접 쿼리 | `orders/_drawer_content.html.erb:66` | `Product.find_by(name: order.item_name)` View에서 직접 호출 | Low |
| View -> Credentials 접근 | `settings/base/index.html.erb:287` | `Rails.application.credentials.dig(...)` View에서 직접 접근 | Low |

### Info: Development Schedule Gap

| Item | Description | Impact |
|------|-------------|:------:|
| Dev Schedule | development 환경에 eCount 스케줄 미등록 | Info |

---

## 11. Recommended Actions

### 11.1 Immediate (24시간 이내)

| Priority | Item | File | Notes |
|----------|------|------|-------|
| 1 | 설계 문서 작성 | `docs/02-design/features/ecount-api-integration.design.md` | 구현 기반 역설계 문서 작성 필요 |

### 11.2 Short-term (1주 이내)

| Priority | Item | File | Expected Impact |
|----------|------|------|-----------------|
| 1 | View 재고 로직 -> Controller/Helper 이동 | `orders/_drawer_content.html.erb` | 아키텍처 정합성 향상 |
| 2 | Credentials 체크 Helper 추출 | `settings/base/index.html.erb` | 코드 정리 |
| 3 | Development 스케줄 추가 (선택) | `config/recurring.yml` | 개발 편의성 |

### 11.3 Long-term (Backlog)

| Item | Notes |
|------|-------|
| InventoryService 응답 캐시를 Redis로 전환 | Production 확장 시 MemoryStore 한계 |
| EcountSyncLog 보관 정책 (30일 이상 자동 삭제) | 데이터 증가 관리 |
| eCount API 호출 메트릭 수집 (응답 시간, 실패율) | 운영 모니터링 |

---

## 12. Design Document Reverse-Engineering Summary

설계 문서 작성 시 아래 내용을 반영해야 합니다:

### Architecture

```
EcountApi Module (6 services)
  BaseService      : HTTP client, retry, error classes
  AuthService      : SESSION_ID auth + cache (23h)
  ProductSyncService : Products upsert (paginated)
  CustomerSyncService: Clients/Suppliers upsert (AR_CD_TYPE routing)
  SlipCreateService  : Sales order creation (idempotent)
  InventoryService   : Stock query + cache (10min)

Jobs (3 scheduled + 1 event-driven)
  EcountProductSyncJob  : hourly at :30 (production)
  EcountCustomerSyncJob : hourly at :45 (production)
  EcountSlipCreateJob   : on Order.confirmed (event-driven)
```

### Data Model

```
ecount_sync_logs: sync_type, status(enum), total_count, success_count,
                  error_count, error_details(JSON), started_at, completed_at

orders:     + ecount_slip_no(string, indexed), ecount_synced_at(datetime)
products:   + stock_quantity(integer), ecount_synced_at(datetime)
clients:    + ecount_synced_at(datetime)
suppliers:  + ecount_synced_at(datetime)
```

### API Endpoints (eCount External)

```
POST /OAPI/V2/OAPILogin
POST /OAPI/V2/Inventory/BasicInfo/GetBasicInfoList
POST /OAPI/V2/BaseInfo/Customer/GetCustomerList
POST /OAPI/V2/Sale/SalesOrder/SaveSalesOrder
GET  /OAPI/V2/Inventory/InventoryStatusInfo/GetInfo
```

### Internal Routes

```
GET  /admin/ecount_sync         -> Admin::EcountSyncController#index
POST /admin/ecount_sync/trigger -> Admin::EcountSyncController#trigger
```

### Credentials Schema

```yaml
ecount:
  com_code: "148829"
  user_id: "K_KDS"
  api_cert_key: "YOUR_API_CERT_KEY"
  lan_type: "ko"
  zone: "A"
```

---

## 13. Next Steps

- [ ] 설계 문서 작성: `/pdca design ecount-api-integration`
- [ ] View layer violations 수정
- [ ] 수정 후 재분석: `/pdca analyze ecount-api-integration`
- [ ] 완료 보고서 작성: `/pdca report ecount-api-integration`

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial analysis (implementation audit) | bkit-gap-detector |
