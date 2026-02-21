# google-sheets-dashboard Gap Analysis Report

**Date**: 2026-02-21
**Match Rate**: 92% ✅ PASS
**Status**: Above 90% threshold — No iteration required

---

## 영역별 점수

| 영역 | 가중치 | 점수 | 백분율 | 상태 |
|------|:------:|:----:|:------:|:----:|
| 1. Gem 추가 | 10% | 10/10 | 100% | PASS |
| 2. DB 마이그레이션 | 15% | 15/15 | 100% | PASS |
| 3. SheetsSyncLog 모델 | 15% | 13/15 | 87% | PASS |
| 4. SheetsService | 30% | 25/30 | 83% | WARNING |
| 5. SheetsSyncJob | 10% | 10/10 | 100% | PASS |
| 6. DashboardController | 10% | 9/10 | 90% | PASS |
| 7. Routes | 5% | 5/5 | 100% | PASS |
| 8. View | 5% | 5/5 | 100% | PASS |
| **전체** | **100%** | **92/100** | **92%** | **PASS** |

---

## Gap 목록

### HIGH (Design 문서 업데이트 필요)

| # | 항목 | Design | 구현 |
|---|------|--------|------|
| H-1 | Mock 모드 전체 아키텍처 | 미정의 | `mock_mode?`, `run_mock`, `run_real` 분기 |
| H-2 | STATUSES에 "mock" 추가 | `%w[pending success failed]` | `%w[pending success failed mock]` |
| H-3 | sync_orders 컬럼 3개 추가 | 9개 컬럼 | 12개 컬럼 (공급사, 품목, 수량) |

### MEDIUM

| # | 항목 | 비고 |
|---|------|------|
| M-1 | @sheets_mock 인스턴스 변수 | Controller에서 View로 mock 상태 전달 |
| M-2 | 모델 헬퍼 메서드 5개 | `mock?`, `pending?`, `total_count`, `status_label`, `status_color` |
| M-3 | 에러 처리 3단계 | `AuthorizationError` → `Google::Apis::Error` → 일반 |
| M-4 | update_column 사용 | Design의 update! 대신 callbacks 스킵 |

### LOW

| # | 항목 | 비고 |
|---|------|------|
| L-1 | DB 인덱스 2개 추가 | `created_at`, `status` — 성능 개선 |
| L-2 | SPREADSHEET_ID lazy 로딩 | 클래스 상수 → 인스턴스 메서드 memoize |
| L-3 | View Mock 모드 UI | Mock 뱃지 + 안내 배너 추가 |
| L-4 | 동기화 카운트 4항목 | 발주+현장+직원+비자 (Design은 2항목) |

---

## 결론

**Mock 모드 아키텍처**가 Design에 없이 구현됨 — credentials 미등록 환경에서도 동작하도록 한 실용적 확장. sync_orders 컬럼 3개 추가는 Order 모델 데이터를 더 충실히 반영한 결과.

Match Rate 92% — 배포 준비 완료.
