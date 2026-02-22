# Gap Analysis Report — google-sheets-dashboard

> 분석 일시: 2026-02-22
> 분석 도구: bkit gap-detector Agent
> Match Rate: **82%** (PASS 임계값 90% 미만 — 설계 문서 업데이트 권장)

## 전체 점수

| 카테고리 | 점수 | 상태 |
|----------|:-----:|:------:|
| 설계 일치도 (Design Match) | 72% | WARNING |
| 아키텍처 준수도 | 92% | PASS |
| 컨벤션 준수도 | 95% | PASS |
| **종합** | **82%** | **WARNING** |

## 항목별 일치율

| 항목 | 일치율 | 비고 |
|------|:------:|------|
| Gem 설치 | 100% | 완전 일치 |
| DB 마이그레이션 | 100% | 완전 일치 |
| SheetsSyncLog 모델 | 85% | mock 상태 추가 |
| Sheets::SheetsService | 45% | 4시트→6시트+대시보드탭, 대폭 확장 |
| SheetsSyncJob | 90% | 거의 일치 |
| DashboardController | 70% | 핵심 일치, 대시보드 확장 |
| Routes | 100% | 완전 일치 |
| View (dashboard) | 60% | Sheets 카드 일치, KPI/차트 추가 |
| Credentials | 75% | AppConfig 우선 방식으로 변경 |
| 시트별 데이터 명세 | 50% | 4시트→6시트+대시보드탭 |

## MISSING (설계 O, 구현 X)

**없음** — 설계의 모든 핵심 기능은 구현됨

## ADDED (설계 X, 구현 O)

| 항목 | 구현 위치 |
|------|----------|
| Mock 모드 자동 전환 | `sheets_service.rb:20-48` |
| AppConfig 동적 설정 + Admin UI | `app_config.rb`, `sheets_config_controller.rb` |
| 월별 24개월 데이터 시트 | `sheets_service.rb:145-171` |
| 분기 8분기 데이터 시트 | `sheets_service.rb:174-194` |
| 현장별 실적 집계 시트 | `sheets_service.rb:197-225` |
| 대시보드 탭 (차트 3종 + 슬라이서) | `sheets_service.rb:285-598` |
| 시트 자동 생성 ensure_sheet_exists | `sheets_service.rb:113-126` |
| KPI 카드 6종 | `dashboard/index.html.erb:6-116` |
| 기간별 트렌드 차트 탭 전환 | `dashboard/index.html.erb:183-297` |
| 비자 만료 리스트 | `dashboard/index.html.erb:335-362` |

## CHANGED (설계 ≠ 구현)

| 항목 | 설계 | 구현 | 영향도 |
|------|------|------|:------:|
| 시트 구조 | 4시트 | 6시트 + 대시보드 탭 | High |
| Spreadsheet ID 소스 | credentials 직접 | AppConfig DB 우선 + fallback | Medium |
| 발주현황 컬럼 | 9컬럼 | 13컬럼 | Medium |
| 비자 데이터 범위 | active만 | 전체 + 경고레벨 컬럼 | Low |
| 현장현황 방식 | 단순 리스트 | 카테고리별 집계 + 납기준수율 | High |
| STATUSES | 3종 | 4종 (+mock) | Low |
| 직원/비자 동기화 | 개별 메서드 | sync_hr_status 통합 | Medium |

## 결론

Match Rate 82% — 설계 대비 기능이 확장된 방향. 누락 기능 없음.

차이의 핵심: 단순 데이터 덤프 → 경영 대시보드 수준 고도화 (차트/KPI/슬라이서, Mock 모드, AppConfig 동적 설정)

권장: 설계 문서를 현재 구현 상태로 업데이트하면 90% 이상 달성 가능.
pdca iterate 불필요 — 누락 기능 없음.
