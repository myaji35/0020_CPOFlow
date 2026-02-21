# Org Chart Plan

**Feature**: org-chart
**Date**: 2026-02-21
**Phase**: Plan
**Task**: #30

---

## 개요

CPOFlow에 **국가 → 법인 → 부서 → 직원** 4계층 조직도 시스템을 추가합니다.
해외 플랜트 건설 특성(다국가 법인, 현장별 조직)에 맞춰 설계하며,
CSS + Alpine.js 기반 **Tree Chart 시각화**를 제공합니다.

기존 `User.branch`, `Employee.department` 데이터를 흡수하여 조직 구조로 통합합니다.

---

## 기능 요구사항 (FR)

| ID | 기능 | 우선순위 |
|----|------|----------|
| FR-01 | Country(국가) CRUD 관리 | HIGH |
| FR-02 | Company(법인) CRUD 관리 — 국가에 소속 | HIGH |
| FR-03 | Department(부서) CRUD 관리 — 법인에 소속 | HIGH |
| FR-04 | 직원(Employee)을 부서에 배속 | HIGH |
| FR-05 | Tree Chart 시각화 — 국가/법인/부서/직원 계층 표시 | HIGH |
| FR-06 | User를 법인/부서에 연결 (User.branch 대체 or 보완) | MEDIUM |
| FR-07 | 조직도 인쇄/내보내기 (PDF/PNG) | LOW |

---

## 모델 초안

```
Country (국가)
  └── Company (법인)  ← has_many departments
        └── Department (부서)  ← has_many employees (through org_memberships or direct FK)
              └── Employee (직원)  ← 기존 Employee 모델에 department_id FK 추가
```

### 신규 모델
- **Country**: 국가 코드, 이름, 지역(region)
- **Company**: 법인명, 법인 유형(본사/지사/현장법인), country_id FK
- **Department**: 부서명, 부서 코드, company_id FK, parent_department_id (하위 부서 지원)

### 기존 모델 수정
- **Employee**: `department_id` FK 추가 (string `department` 컬럼 보완 또는 대체)
- **User**: `company_id` FK 추가 (string `branch` enum 보완)

---

## UI/UX 계획

### org_chart/index — 트리 차트 메인 화면
```
[국가 탭: UAE | Korea | ...]
  └── [법인 카드: Gagahoho UAE]
        ├── [부서: Engineering]  → 직원 수 배지
        ├── [부서: Procurement]
        └── [부서: HR]
```
- Alpine.js로 펼치기/접기(expand/collapse)
- 각 노드 클릭 시 사이드패널로 상세 표시
- 직원 아바타(이니셜 원형) 표시

### org_chart/show — 특정 법인/부서 드릴다운
- 부서별 직원 목록
- 직원 카드: 이름, 직함, 국적, 비자 상태

### companies/, departments/ — CRUD 관리 페이지
- Admin/Manager 전용

---

## 기존 데이터 연동 전략

| 기존 데이터 | 신규 모델 | 처리 방법 |
|------------|----------|----------|
| `User.branch` (abu_dhabi/seoul) | Company | enum을 company_id FK로 점진적 대체, 기존 enum 유지 병행 |
| `Employee.department` (string) | Department | department_id 추가 후 마이그레이션으로 매핑 |

---

## 구현 순서

1. 마이그레이션: countries, companies, departments 생성
2. Employee에 `department_id` FK 추가 마이그레이션
3. User에 `company_id` FK 추가 마이그레이션
4. 모델 3개 (Country, Company, Department)
5. 컨트롤러 (OrgChart::CompaniesController, OrgChart::DepartmentsController, OrgChartController)
6. Tree Chart 뷰 (Alpine.js 펼치기/접기)
7. Sidebar에 조직도 링크 추가
8. Seeds 업데이트 (UAE/Korea 국가, 법인, 부서 샘플)

---

## 제약 및 고려사항

- **외부 라이브러리 없음**: D3.js, mermaid 등 미사용. 순수 HTML/CSS/Alpine.js로 구현
- **점진적 마이그레이션**: 기존 `User.branch`, `Employee.department` string을 즉시 제거하지 않고 병행 유지
- **MenuPermission 연동**: `org_chart` 메뉴키를 MenuPermission::MENU_KEYS에 추가
