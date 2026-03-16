# kanban-rename Analysis Report

> **Analysis Type**: Gap Analysis (Plan vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector (Claude)
> **Date**: 2026-03-16
> **Plan Doc**: [kanban-rename.plan.md](../01-plan/features/kanban-rename.plan.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Plan 문서(칸반 보드 7단계 -> 8단계 리네이밍)의 모든 요구사항이 실제 코드에 반영되었는지 전수 조사.
기존 status 이름(inbox, reviewing, quoted, confirmed, procuring, qa, delivered)이 칸반 status 문맥으로 잔존하는 곳을 식별.

### 1.2 Analysis Scope

- **Plan Document**: `docs/01-plan/features/kanban-rename.plan.md`
- **Implementation Path**: `app/` (models, controllers, services, views, helpers, jobs, seeds)
- **Analysis Date**: 2026-03-16

### 1.3 제외 대상 (Plan 문서 비변경 사항 + 분석 요청 기준)

- URL/라우트 이름: `inbox_path`, `inbox#show`, `/inbox/` 등
- rfq_status 관련: `:rfq_confirmed`, `:rfq_uncertain` 등 (별도 enum)
- rfq_detector_service의 `:confirmed` (RFQ verdict, 칸반 status 아님)
- 변수명: `@delivered_this_month`, `delivered_count` 등
- 마이그레이션 파일
- CSS 클래스: `.inbox-layout`, `.inbox-search` 등 (UI 스타일 클래스)
- `inbox_ai` 캐시 키

---

## 2. Gap Analysis (Plan vs Implementation)

### 2.1 Phase 1: 핵심 모델 변경 (Order.rb)

| 요구사항 | 구현 상태 | 상세 |
|----------|:---------:|------|
| enum :status 8개 정의 (new_rfq~give_up) | ✅ | `app/models/order.rb:19-28` |
| DB 정수값 0~6 유지, give_up=7 신규 | ✅ | 매핑 정확 |
| KANBAN_COLUMNS 8개 확장 | ✅ | `order.rb:60` |
| STATUS_LABELS 영문(한글) 형식 | ✅ | `order.rb:62-71` |
| active scope: get_grn, give_up 제외 | ✅ | `order.rb:52` |
| overdue scope: get_grn, give_up 제외 | ✅ | `order.rb:53` |
| urgent scope: get_grn, give_up 제외 | ✅ | `order.rb:54` |
| due_soon scope: get_grn, give_up 제외 | ✅ | `order.rb:55` |
| default: :new_rfq | ✅ | `order.rb:28` |

**Phase 1 결과: 9/9 (100%)**

### 2.2 Phase 2: 컨트롤러/서비스 일괄 치환

| 파일 | 요구사항 | 구현 상태 | 상세 |
|------|----------|:---------:|------|
| `kanban_controller.rb` | KANBAN_COLUMNS 참조 | ✅ | Order::KANBAN_COLUMNS 사용 |
| `inbox_controller.rb` | `:inbox` -> `:new_rfq` | ✅ | line 19,21,23,53 모두 `:new_rfq` |
| `orders_controller.rb` | status 참조 | ✅ | line 77 `:new_rfq`, line 164 `:new_rfq` |
| `orders/bulk_controller.rb` | STATUS_LABELS 참조 | ✅ | Order::STATUS_LABELS 사용 |
| `reports_controller.rb` | 리포트 집계 | ✅ | `Order.get_grn` scope 사용, give_up 제외 |
| `search_controller.rb` | 검색 필터 | ✅ | STATUS_LABELS 참조만 |
| `clients_controller.rb` | 상태 필터 | ✅ | `:get_grn`, `:give_up` 사용 |
| `suppliers_controller.rb` | 상태 필터 | ✅ | `:get_grn`, `:give_up` 사용 |
| `dashboard_controller.rb` | KPI 집계 | ✅ | `Order.get_grn`, `"get_grn"` 사용 |
| `application_helper.rb` | 상태 표시 헬퍼 | ✅ | 새 enum 이름 8개 사용 |
| `gmail/email_to_order_service.rb` | 신규 Order 기본 상태 | ✅ | line 38 `:new_rfq` |
| `gmail/rfq_detector_service.rb` | RFQ 판정 | ✅ | rfq_verdict만 사용 (칸반 status 아님) |
| `risk_assessment_service.rb` | 리스크 계산 | ✅ | 새 enum 이름 + give_up 포함 |
| `google_chat_service.rb` | 알림 메시지 | -- | 파일에 status 참조 없음 (STATUS_LABELS 간접 참조) |
| `email_sync_job.rb` | 동기화 후 상태 | ✅ | rfq_verdict만 사용 |
| `due_notification_job.rb` | 알림 대상 필터 | ✅ | `:get_grn`, `:give_up` 제외 |
| `activity.rb` | 상태 변경 이력 | ✅ | 정수값 기반, 변경 불필요 |
| `client.rb` | 클라이언트 연관 | ✅ | `:get_grn`, `:give_up` 사용 |
| `rfq_feedback.rb` | 피드백 | ✅ | rfq verdict만 (별도 scope) |
| **sheets_service.rb** | **시트 동기화** | **❌ 미변환** | **아래 상세 참조** |

**Phase 2 결과: 19/20 (95%) -- sheets_service.rb 미변환**

### 2.3 Phase 3: 뷰 일괄 치환

| 파일 | 구현 상태 | 상세 |
|------|:---------:|------|
| `kanban/index.html.erb` | ✅ | 새 enum 참조, 색상 정상 |
| `kanban/_card.html.erb` | ✅ | STATUS_LABELS 간접 참조 |
| `inbox/index.html.erb` | ✅ | status_colors 해시에 새 이름 + give_up |
| `inbox/show.html.erb` | -- | index에 통합 |
| `dashboard/index.html.erb` | ✅ | 새 status_colors 해시 + give_up |
| `orders/index.html.erb` | ✅ | 새 status 이름 사용 |
| `orders/show.html.erb` | ✅ | STATUS_LABELS 참조 |
| `orders/_drawer_content.html.erb` | ✅ | 새 status_colors 해시 + give_up |
| `reports/index.html.erb` | ✅ | 새 enum 이름 + give_up |
| `clients/show.html.erb` | ✅ | STATUS_LABELS 참조 |
| `suppliers/show.html.erb` | ✅ | 새 status_colors + give_up |
| `calendar/index.html.erb` | ✅ | STATUS_LABELS 참조 |
| `shared/_sidebar.html.erb` | **❌** | **`Order.inbox.count` 잔존** |
| `contact_persons/show.html.erb` | ✅ | 새 enum 이름 + give_up |
| `projects/show.html.erb` | ✅ | 새 status_colors + give_up |
| `layouts/application.html.erb` | ✅ | JS KANBAN_COLUMNS 새 이름 |

**Phase 3 결과: 14/15 (93%) -- sidebar Order.inbox 잔존**

### 2.4 Phase 4: 시드/테스트 데이터

| 파일 | 구현 상태 | 상세 |
|------|:---------:|------|
| `db/seeds.rb` 오더 생성 | ✅ | line 132~182: `:new_rfq`, `:make_quo`, `:pending_po` 등 새 이름 사용 |
| `db/seeds.rb` 태스크 생성 | **❌** | **line 193: `Order.find_by(status: "reviewing")` 잔존** |

**Phase 4 결과: 1/2 (50%)**

### 2.5 Give Up 단계 구현 검증

| 요구사항 | 구현 상태 | 위치 |
|----------|:---------:|------|
| enum give_up: 7 | ✅ | `order.rb:27` |
| KANBAN_COLUMNS에 포함 | ✅ | `order.rb:60` |
| STATUS_LABELS에 포함 | ✅ | `order.rb:70` |
| active scope에서 제외 | ✅ | `order.rb:52` |
| overdue scope에서 제외 | ✅ | `order.rb:53` |
| urgent/due_soon scope에서 제외 | ✅ | `order.rb:54-55` |
| 칸반 보드 칼럼 색상 | ✅ | 뷰 status_colors: `"bg-gray-200"` |
| 어느 단계에서든 이동 가능 | ✅ | 칸반 드래그&드롭 + 상태 변경 API 제한 없음 |
| client.rb active_orders_count 제외 | ✅ | `client.rb:20` |
| risk_assessment_service 제외 | ✅ | `risk_assessment_service.rb:26,46` |
| due_notification_job 제외 | ✅ | `due_notification_job.rb:30` |
| dashboard 담당자 워크로드 제외 | ✅ | `dashboard_controller.rb:45` |

**Give Up 결과: 12/12 (100%)**

---

## 3. 잔존 Gap 상세

### 3.1 [GAP-01] sheets_service.rb -- `status: "delivered"` 다수 잔존 (CRITICAL)

**파일**: `app/services/sheets/sheets_service.rb`
**영향**: Google Sheets 동기화 기능의 통계가 잘못 집계됨

| 위치 | 현재 코드 | 올바른 코드 |
|------|----------|------------|
| line 154 | `mo.where(status: "delivered")` | `mo.where(status: "get_grn")` |
| line 162 | `mo.where.not(status: "delivered")` | `mo.where.not(status: "get_grn")` |
| line 182 | `orders.where(status: "delivered")` | `orders.where(status: "get_grn")` |
| line 203 | `po.where(status: "delivered")` | `po.where(status: "get_grn")` |
| line 216 | `un.where(status: "delivered")` | `un.where(status: "get_grn")` |
| line 345 | `Order.where.not(status: "delivered")` | `Order.where.not(status: "get_grn")` |
| line 346 | `Order.where.not(status: "delivered")` | `Order.where.not(status: "get_grn")` |
| line 347 | `Order.where(status: "delivered", ...)` | `Order.where(status: "get_grn", ...)` |
| line 350 | `Order.where(status: "delivered", ...)` | `Order.where(status: "get_grn", ...)` |

**총 9건**. 실제 DB에서 `status: "delivered"`로 쿼리하면 **결과가 0건** 반환됨 (enum 문자열이 이제 "get_grn"이므로).
단, Rails enum은 정수 매핑이므로 `where(status: "delivered")`는 존재하지 않는 enum 값을 참조하여 **ArgumentError** 발생 가능.

**심각도**: 높음 -- Google Sheets KPI 대시보드 동기화가 완전히 깨짐

### 3.2 [GAP-02] _sidebar.html.erb -- `Order.inbox.count` 잔존

**파일**: `app/views/shared/_sidebar.html.erb:15`
**현재**: `<% rfq_count = Order.inbox.count %>`
**올바른**: `<% rfq_count = Order.new_rfq.count %>`

Rails enum은 `enum :status, { new_rfq: 0, ... }` 선언 시 `Order.new_rfq` scope를 자동 생성하지만, `Order.inbox` scope는 더 이상 존재하지 않음.

**심각도**: 높음 -- 모든 페이지의 사이드바 렌더링 시 **NoMethodError** 발생

### 3.3 [GAP-03] db/seeds.rb -- `Order.find_by(status: "reviewing")` 잔존

**파일**: `db/seeds.rb:193`
**현재**: `order = Order.find_by(status: "reviewing")`
**올바른**: `order = Order.find_by(status: "make_quo")`

`"reviewing"`은 더 이상 유효한 enum 값이 아니므로 **ArgumentError** 발생. 시드 실행 시 크래시.

**심각도**: 중간 -- 개발환경 시드 실행에만 영향

### 3.4 [GAP-04] sheets_service.rb -- give_up 미반영

`sheets_service.rb`의 `where.not(status: "delivered")` 패턴은 `"get_grn"`으로 변경 후에도 `give_up`을 추가 제외해야 하는지 검토 필요.
- line 162: 진행중 건수 = `where.not(status: "delivered")` --> 이 로직은 `active` scope로 대체하는 것이 바람직
- line 345-346: 동일

**심각도**: 낮음 -- give_up 건이 "진행중"에 포함되는 미세 오차

---

## 4. 분석에서 제외된 항목 (정상 잔존)

다음은 기존 이름이 코드에 존재하지만, 칸반 status 문맥이 아니므로 변경 대상이 아닙니다:

| 패턴 | 이유 | 예시 |
|------|------|------|
| `inbox_path`, `/inbox/` | URL/라우트 (변경 대상 아님) | `redirect_to inbox_path` |
| `.inbox-layout`, `.inbox-search` | CSS 클래스명 | `inbox/index.html.erb:4` |
| `inbox-search` ID | HTML element ID | `inbox/index.html.erb:167` |
| `rfq_verdict == :confirmed` | RFQ 판정 verdict (별도 시스템) | `email_sync_job.rb:77` |
| `rfq_confirmed`, `rfq_excluded` | rfq_status enum (별도) | `order.rb:31-33` |
| `@delivered_this_month` | 변수명 | `dashboard_controller.rb:7` |
| `delivered:` (hash key) | 해시 키 | `reports_controller.rb:64` |
| `lni lni-inbox` | 아이콘 클래스 | `kanban/index.html.erb:93` |
| `MenuPermission inbox` | 메뉴 키 | `menu_permission.rb:3` |
| 주석 내 "inbox" | 주석 (실행에 영향 없음) | `email_to_order_service.rb:142` |
| `rfq_detector_service.rb`의 `/delivered/i` | 이메일 패턴 매칭 정규식 | line 76 |

---

## 5. Match Rate Summary

```
+---------------------------------------------+
|  Overall Match Rate: 93%                     |
+---------------------------------------------+
|  Phase 1 (핵심 모델):       9/9   (100%)     |
|  Phase 2 (컨트롤러/서비스): 19/20 ( 95%)     |
|  Phase 3 (뷰):             14/15 ( 93%)     |
|  Phase 4 (시드):            1/2  ( 50%)     |
|  Give Up 단계:             12/12 (100%)     |
+---------------------------------------------+
|  총 항목: 57개                               |
|  ✅ 일치: 55개 (96.5%)                       |
|  ❌ 미반영: 2개 (GAP-01, GAP-02)             |
|  ⚠️ 시드 잔존: 1개 (GAP-03)                  |
+---------------------------------------------+
```

### Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match (enum/scope/label) | 100% | ✅ |
| Controller/Service 치환 | 95% | ⚠️ |
| View 치환 | 93% | ⚠️ |
| Seed 데이터 | 50% | ❌ |
| Give Up 신규 단계 | 100% | ✅ |
| **Overall** | **93%** | **⚠️** |

---

## 6. Recommended Actions

### 6.1 Immediate (런타임 크래시 방지)

| Priority | Item | File | 영향도 |
|----------|------|------|--------|
| 1 | `Order.inbox` -> `Order.new_rfq` | `app/views/shared/_sidebar.html.erb:15` | 전 페이지 크래시 |
| 2 | `status: "delivered"` -> `"get_grn"` (9곳) | `app/services/sheets/sheets_service.rb` | Sheets 동기화 크래시 |
| 3 | `status: "reviewing"` -> `"make_quo"` | `db/seeds.rb:193` | 시드 크래시 |

### 6.2 선택 개선 (give_up scope 정합성)

| Priority | Item | File | 영향도 |
|----------|------|------|--------|
| 4 | sheets_service 진행중 집계에 give_up 제외 추가 | `sheets_service.rb:162,345-346` | 미세 통계 오차 |

---

## 7. Synchronization Option

```
권장: Option 1 -- 구현을 Plan에 맞추어 수정

수정 대상 3개 파일, 총 12건의 문자열 치환:
  1. sheets_service.rb: "delivered" -> "get_grn" (9건)
  2. _sidebar.html.erb: Order.inbox -> Order.new_rfq (1건)
  3. seeds.rb: "reviewing" -> "make_quo" (1건)
  4. (선택) sheets_service.rb: give_up 제외 추가 (3건)
```

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-03-16 | Initial gap analysis | bkit-gap-detector |
