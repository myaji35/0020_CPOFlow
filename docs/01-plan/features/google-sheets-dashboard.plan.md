# Feature Plan: google-sheets-dashboard

**Feature Name**: Google Sheets 대시보드 연동
**Created**: 2026-02-21
**Phase**: Plan

---

## 개요

CPOFlow의 핵심 데이터(발주, 현장, 직원, 비자)를 Google Sheets로 자동 동기화하여,
경영진이 별도 로그인 없이 Google Sheets에서 실시간 KPI를 조회할 수 있도록 한다.

기존에 Gmail OAuth2 토큰(googleauth + google-apis-gmail_v1)이 구현되어 있으므로,
같은 OAuth 인프라를 재활용하여 Sheets API를 추가한다.

---

## 목표

- CPOFlow 데이터를 지정한 Google Spreadsheet에 자동 Push
- 대시보드 뷰에서 수동 동기화 버튼 제공
- (선택) 주기적 자동 동기화 (ActiveJob + Solid Queue)

---

## 기능 요구사항

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-01 | Google Sheets API 연동 (Service Account 방식) | HIGH |
| FR-02 | Spreadsheet ID 설정 (Settings 또는 ENV) | HIGH |
| FR-03 | 시트별 데이터 Push: 발주, 현장, 직원, 비자 만료 | HIGH |
| FR-04 | 대시보드 페이지에 "Sheets 동기화" 버튼 + 상태 표시 | HIGH |
| FR-05 | 동기화 로그 (성공/실패 시각, 건수) | MEDIUM |
| FR-06 | 자동 동기화 스케줄 (1일 1회, Solid Queue) | LOW |

---

## 기술 결정

| 항목 | 선택 | 이유 |
|------|------|------|
| 인증 방식 | **Service Account JSON** | OAuth User Flow 대비 서버간 인증 단순, 재갱신 불필요 |
| Gem | `google-apis-sheets_v4` | 기존 googleauth 재사용 가능 |
| Push 방식 | `batchUpdate` (values.update) | 시트 전체 덮어쓰기 방식, 심플 |
| 스케줄 | Solid Queue (Rails 8 기본) | 별도 인프라 없이 SQLite 기반 |

---

## 범위 (이번 사이클)

**포함**
- Service Account 연동 설정
- 4개 시트 Push (발주, 현장, 직원, 비자만료)
- 수동 동기화 버튼 (대시보드)
- 동기화 결과 로그 DB 저장

**제외 (다음 사이클)**
- Google Sheets → CPOFlow 역방향 동기화
- Sheets 내 수식/차트 자동 생성
- 사용자별 개인 Spreadsheet 연결

---

## 연관 기존 기능

- `app/services/gmail_oauth_service.rb` — OAuth 패턴 참조
- `app/models/user.rb` — google_token 관련 필드
- `app/controllers/dashboard_controller.rb` — 동기화 버튼 추가 위치
- `config/credentials.yml.enc` — Service Account JSON 저장 위치
