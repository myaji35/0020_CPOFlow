# Plan: kanban-rename — 칸반 보드 단계 리네이밍 (7→8단계)

**Feature**: kanban-rename
**Created**: 2026-03-16
**Origin**: 2026.03.13 회의 안건 #2
**Phase**: Plan

---

## 1. 배경 및 목적

현재 CPOFlow 칸반 보드는 7단계(`inbox → reviewing → quoted → confirmed → procuring → qa → delivered`)로 운영 중이나, 실제 조달 업무 흐름과 용어가 맞지 않아 사용자 혼선 발생.

대표님이 현장 업무에 맞는 이름으로 8단계 리네이밍 요청 (2026.03.13 회의).

## 2. 변경 매핑

| # | 기존 enum | 기존 라벨 | 새 enum | 새 라벨 | DB 정수값 | 의미 |
|---|----------|----------|---------|---------|----------|------|
| 1 | `inbox` | Inbox | `new_rfq` | New | 0 | 신규 RFQ 수신 |
| 2 | `reviewing` | Under Review | `make_quo` | Make QUO | 1 | 견적서 작성 중 |
| 3 | `quoted` | Quoted | `pending_po` | Pending PO | 2 | PO(발주서) 대기 |
| 4 | `confirmed` | Order Confirmed | `new_po` | New PO | 3 | 신규 발주 확정 |
| 5 | `procuring` | Procuring | `delivery_items` | Delivery Items | 4 | 물품 조달/배송 |
| 6 | `qa` | QA Inspection | `problem` | Problem | 5 | 문제 발생 건 |
| 7 | `delivered` | Delivered | `get_grn` | Get GRN | 6 | 물품수령확인서(GRN) 수령 |
| 8 | *(신규)* | — | `give_up` | Give Up | 7 | 포기/취소 건 |

**핵심 원칙**: DB 정수값(0~6) 매핑은 유지 → 기존 데이터 마이그레이션 불필요. `give_up(7)`만 신규 추가.

## 3. 영향 범위 분석

### 3.1 Model/Service (Ruby 파일 — 24개)

| 파일 | 변경 내용 | 난이도 |
|------|----------|-------|
| `app/models/order.rb` | enum 정의, KANBAN_COLUMNS, STATUS_LABELS | **핵심** |
| `app/controllers/kanban_controller.rb` | KANBAN_COLUMNS 참조 | 자동 반영 |
| `app/controllers/inbox_controller.rb` | `status: :inbox` → `:new_rfq` | 중 |
| `app/controllers/orders_controller.rb` | status 참조 | 중 |
| `app/controllers/orders/bulk_controller.rb` | bulk 상태 변경 | 중 |
| `app/controllers/reports_controller.rb` | 리포트 집계 | 중 |
| `app/controllers/search_controller.rb` | 검색 필터 | 하 |
| `app/controllers/clients_controller.rb` | 상태 필터 | 하 |
| `app/controllers/suppliers_controller.rb` | 상태 필터 | 하 |
| `app/helpers/application_helper.rb` | 상태 표시 헬퍼 | 중 |
| `app/services/gmail/email_to_order_service.rb` | 신규 Order 생성 시 기본 상태 | 중 |
| `app/services/gmail/rfq_detector_service.rb` | RFQ 판정 후 상태 | 하 |
| `app/services/gmail/llm_rfq_analyzer_service.rb` | 분석 결과 | 하 |
| `app/services/risk_assessment_service.rb` | 리스크 계산 | 하 |
| `app/services/google_chat_service.rb` | 알림 메시지 | 하 |
| `app/jobs/email_sync_job.rb` | 동기화 후 상태 | 하 |
| `app/jobs/due_notification_job.rb` | 알림 대상 필터 | 하 |
| `app/models/activity.rb` | 상태 변경 이력 | 하 |
| `app/models/client.rb` | 클라이언트 연관 | 하 |
| `app/models/rfq_feedback.rb` | 피드백 | 하 |
| `db/seeds.rb` | 시드 데이터 | 하 |
| `db/seeds/mockup_data.rb` | 목업 데이터 | 하 |
| `config/routes.rb` | 라우트 (status 파라미터 화이트리스트) | 하 |

### 3.2 View (ERB 파일 — 25개)

| 파일 | 변경 내용 | 난이도 |
|------|----------|-------|
| `app/views/kanban/index.html.erb` | 칼럼 헤더, 색상 매핑 | **핵심** |
| `app/views/kanban/_card.html.erb` | 카드 상태 표시 | 중 |
| `app/views/inbox/index.html.erb` | status_colors 해시, 필터 | **핵심** |
| `app/views/inbox/show.html.erb` | 상태 표시 | 중 |
| `app/views/dashboard/index.html.erb` | KPI 집계 | 중 |
| `app/views/orders/index.html.erb` | 상태 필터/배지 | 중 |
| `app/views/orders/show.html.erb` | 상태 표시 | 중 |
| `app/views/orders/_drawer_content.html.erb` | 드로어 상태 | 중 |
| `app/views/orders/_sidebar_panel.html.erb` | 사이드바 | 중 |
| `app/views/reports/index.html.erb` | 리포트 | 중 |
| `app/views/clients/index.html.erb` | 클라이언트 상태 | 하 |
| `app/views/clients/show.html.erb` | 클라이언트 상세 | 하 |
| `app/views/suppliers/show.html.erb` | 거래처 상세 | 하 |
| `app/views/calendar/index.html.erb` | 캘린더 | 하 |
| `app/views/shared/_sidebar.html.erb` | 메뉴 | 하 |
| 기타 10개 뷰 | 간접 참조 (mailer, devise 등) | 하 |

### 3.3 give_up 신규 단계 관련

- **어느 단계에서든** Give Up으로 이동 가능 (완료 상태와 유사)
- `active` scope 수정 필요: `where.not(status: [:get_grn, :give_up])`
- `overdue` scope 수정 필요: 동일
- Give Up 사유 입력은 향후 확장 (현재는 상태 이동만)
- 칸반 보드에서 Give Up 칼럼 색상: `bg-red-100 text-red-700` (위험/포기)

## 4. 구현 전략

### Phase 1: 핵심 모델 변경 (Order.rb)
1. `enum :status` 정의 변경 (기존 정수값 유지)
2. `KANBAN_COLUMNS` 8개로 확장
3. `STATUS_LABELS` 업데이트
4. `active`, `overdue`, `urgent`, `due_soon` scope 수정

### Phase 2: 컨트롤러/서비스 일괄 치환
- 모든 `.rb` 파일에서 기존 enum 이름 → 새 enum 이름 치환
- `grep -r` 기반 전수 조사 후 일괄 변경

### Phase 3: 뷰 일괄 치환
- `status_colors` 해시 업데이트 (+ give_up 색상 추가)
- 칸반 뷰 칼럼 헤더/색상 업데이트
- 모든 ERB에서 기존 상태명 참조 치환

### Phase 4: 시드/테스트 데이터 업데이트
- `db/seeds.rb`, `db/seeds/mockup_data.rb`

### Phase 5: 스모크 테스트
- `bin/rails runner` 로 모델 검증
- 주요 페이지 HTTP 200 확인

## 5. 리스크 및 주의사항

| 리스크 | 대응 |
|-------|------|
| 기존 DB 데이터의 정수값 매핑 깨짐 | 정수값 0~6 유지, give_up=7만 신규 → 마이그레이션 불필요 |
| 프로덕션 배포 시 enum 불일치 | 코드 배포와 동시에 반영 (DB 변경 없음) |
| Give Up 건의 집계 제외 | `active` scope에서 `give_up` 제외 확인 |
| 기존 Activity 이력의 from/to_status 정수값 | 정수값 기반이므로 자동 호환 |

## 6. 비변경 사항

- DB 마이그레이션: **없음** (enum 정수값 유지)
- API 엔드포인트 URL: **변경 없음** (status 파라미터 값만 변경)
- 기존 Activity 이력: **호환** (정수값 저장)

---

*Plan 작성 완료. 다음 단계: `/pdca design kanban-rename` 또는 바로 구현 착수*
