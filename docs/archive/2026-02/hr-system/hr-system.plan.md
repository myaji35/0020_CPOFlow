# HR System Plan

**Feature**: hr-system
**Date**: 2026-02-21
**Phase**: Plan (Completed)

---

## 개요

CPOFlow에 HR(인사) 관리 시스템을 추가합니다. 해외 플랜트 건설 현장 특성에 맞춰 비자/계약/현장배정/자격증 관리와 사전 만료 알림 기능을 구현합니다.

---

## 기능 요구사항 (FR)

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-01 | 직원 기본정보 관리 (다국적 지원) | HIGH |
| FR-02 | 비자 관리 및 만료 선제 알림 (D-60/30/14) | HIGH |
| FR-03 | 근로계약 관리 및 만료 알림 (D-30/14) | HIGH |
| FR-04 | 현장 배정 이력 관리 | MEDIUM |
| FR-05 | 자격증/면허 관리 | MEDIUM |
| FR-06 | 역할별 메뉴 권한 관리 (MenuPermission) | HIGH |

---

## 모델 초안

- `Employee`: 직원 기본정보 (이름, 국적, 여권번호, 고용형태 등)
- `Visa`: 비자 정보 (종류, 발급국, 만료일, 상태)
- `EmploymentContract`: 근로계약 (기간, 급여, 통화, 상태)
- `EmployeeAssignment`: 현장 배정 (직원-프로젝트 연결)
- `Certification`: 자격증/면허 (명칭, 발급기관, 만료일)
- `MenuPermission`: 역할별 메뉴 CRUD 권한

---

## UI/UX 계획

- employees/index: 통계 카드(4개) + 검색/필터 + 비자/계약 배지 테이블
- employees/show: Alpine.js 5탭 UI (기본정보/비자/계약/현장배정/자격증)
- settings/menu_permissions: 역할 탭 + CRUD 체크박스 매트릭스

---

## 구현 순서

1. 마이그레이션 6개 생성
2. 모델 7개 (Employee, Visa, EmploymentContract, EmployeeAssignment, Certification, MenuPermission, Project 수정)
3. 컨트롤러 6개
4. 뷰 파일 20+개
5. HrExpiryNotificationJob + recurring.yml 스케줄
6. Seeds 업데이트
7. Sidebar + 프로젝트 연동
