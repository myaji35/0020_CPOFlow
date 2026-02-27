# Feature Plan: phase4-hr

**Feature Name**: Phase 4 HR 완성 (직원·조직도·팀 Gap 보완)
**Created**: 2026-02-28
**Phase**: Plan

---

## 개요

Phase 4 HR 기능(직원 관리, 조직도, 팀 현황)은 **이미 90% 구현 완료** 상태다.
모델·컨트롤러·뷰·라우트·i18n이 모두 갖춰져 있으며 실제 데이터(직원 11명, 비자 11건 등)도 존재한다.

이번 사이클은 **나머지 10% Gap만 정확히 보완**하여 Phase 4를 완전 완성한다.

---

## AS-IS 현황 (이미 구현됨)

| 항목 | 상태 |
|------|:----:|
| Employee CRUD (목록/상세/등록/수정/삭제) | ✅ |
| Visa CRUD (nested under employee) | ✅ |
| EmploymentContract CRUD | ✅ |
| EmployeeAssignment CRUD | ✅ |
| Certification CRUD | ✅ |
| 조직도 (국가→법인→부서→직원 계층) | ✅ |
| 팀 현황 (워크로드 카드, show 페이지) | ✅ |
| 대시보드 비자 만료 임박 섹션 | ✅ |
| 사이드바 직원관리/조직도 링크 | ✅ |
| i18n (KO/EN) | ✅ |
| 직원 index 통계 카드 (만료 임박 건수) | ✅ |
| 직원 index 비자 만료 경고 배너 | ✅ |

---

## TO-DO Gap (이번 구현 대상)

### FR-01: 대시보드 계약 만료 임박 섹션 추가
- **위치**: `app/views/dashboard/index.html.erb` — 비자 만료 섹션 아래
- **현재**: 비자 만료 섹션만 있음
- **필요**: 계약 만료 임박 직원 목록 (30일 이내) 카드 추가
- **Controller**: `dashboard_controller.rb`에 `@expiring_contracts` 변수 추가

### FR-02: Team show 페이지 강화 (FR-05 이월분)
- **위치**: `app/views/team/show.html.erb`
- **현재**: 진행 중 주문 목록만 표시
- **필요**: 담당자별 상태별 오더 통계 뱃지 (Inbox N / Delivered N 등)
- **Controller**: `team_controller.rb` show 액션에 `@status_counts` 추가

### FR-03: 직원 index — 부서 필터 수정
- **현재**: `params[:department]`로 문자열 필터 → department_id가 생긴 후 연결 끊김
- **필요**: `department_id` 기준 필터로 변경
- **Controller**: `employees_controller.rb` line 13 수정

### FR-04: Employee 모델 — `current_project` 헬퍼 추가
- **현재**: `current_assignment&.project` 패턴이 뷰마다 중복
- **필요**: `current_project` 편의 메서드 추가

### FR-05: 조직도 — 부서 없는 직원 표시
- **현재**: `department_id: nil` 직원이 조직도에 미표시
- **필요**: 부서 미배정 직원 섹션 ("미배정" 그룹) 추가

---

## 기능 요구사항

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-01 | 대시보드 계약 만료 임박 카드 | HIGH |
| FR-02 | Team show 상태별 오더 통계 뱃지 | HIGH |
| FR-03 | 직원 index 부서 필터 → department_id 기준 수정 | MEDIUM |
| FR-04 | Employee#current_project 메서드 추가 | MEDIUM |
| FR-05 | 조직도 부서 미배정 직원 섹션 | LOW |

---

## 기술 결정

| 항목 | 선택 | 이유 |
|------|------|------|
| 계약 만료 섹션 | 비자 섹션과 동일 패턴 재사용 | 일관성 |
| 부서 필터 | `department_id` FK join | `department` 문자열 컬럼은 레거시 |
| 조직도 미배정 | 별도 섹션, 법인 외부 렌더링 | 계층 구조 훼손 방지 |

---

## 범위 (이번 사이클)

**포함**
- FR-01 ~ FR-05 Gap 보완 (5개 항목)
- 수정 파일: 최대 7개

**제외 (다음 사이클)**
- HR 알림 이메일/Notification Job
- 직원 사진 업로드
- 급여 관리 모듈
- 외부 HR 시스템 연동

---

## 연관 파일

- `app/controllers/dashboard_controller.rb` — @expiring_contracts 추가
- `app/controllers/team_controller.rb` — show @status_counts 추가
- `app/controllers/employees_controller.rb` — 부서 필터 수정
- `app/models/employee.rb` — current_project 메서드 추가
- `app/views/dashboard/index.html.erb` — 계약 만료 섹션 추가
- `app/views/team/show.html.erb` — 상태별 통계 뱃지 추가
- `app/views/org_chart/index.html.erb` — 미배정 직원 섹션 추가
