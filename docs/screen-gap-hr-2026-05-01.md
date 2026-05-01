# HR 모듈 화면 갭 분석 (ISS-294)

## 1. 분석 범위

- **분석 일시**: 2026-05-01
- **대상 화면**: 18개 (뷰 파일 기준)
  - `/employees` index, new, edit, show
  - `/employees/:id/visas` (new, edit)
  - `/employees/:id/employment_contracts` (new, edit)
  - `/employees/:id/employee_assignments` (new, edit)
  - `/employees/:id/certifications` (new, edit)
  - `/org_chart` index
  - `/org_chart/companies` index, show
  - `/org_chart/countries` index, show
  - `/org_chart/companies/:id/departments` show
  - `/employees/departments`, `/employees/job_titles` (인라인 모달)
- **체크리스트 항목**: 27개 (목록 7 + 상세 6 + 폼 5 + 대시보드 3 + 인사 특화 10 × 복수 화면)

---

## 2. 갭 요약

| 등급 | 건수 |
|------|------|
| CRITICAL | 5 |
| HIGH | 7 |
| MEDIUM | 6 |
| LOW | 3 |
| **합계** | **21** |

---

## 3. 화면별 상세

### `/employees` (index)

**충족**
- 검색 박스 (이름 LIKE 검색) ✅
- 고용형태 / 부서 / 직책 필터 ✅
- 퇴직자 포함 토글 ✅
- 파견중 필터 ✅
- 재직중 기본 노출 ✅
- 비자 만료 임박 배너 (60일 기준) ✅
- KPI 카드 4종 (총 직원, 파견중, 비자 만료, 계약 만료) ✅
- 신규 등록 버튼 (member 이상) ✅
- 빈 상태 메시지 ✅

**부분**
- 정렬: 이름 오름차순 고정(`by_name` scope). 컬럼 클릭 정렬 없음.
- 검색: 이름 필드만 (`name`, `name_en`). 여권번호·전화번호 등 다른 필드 검색 불가.

**부재**
- 페이지네이션: `pagy` Gem이 설치되어 있으나 `EmployeesController#index`에서 미사용. 직원이 100명을 넘으면 전체 로드.
- 일괄 내보내기 (CSV/Excel): 없음.
- 일괄 작업 (대량 상태 변경 등): 없음.
- 자격증 만료 임박 알림: 비자·계약은 KPI에 있으나 자격증은 없음.

**발견 갭**
- [HIGH] 페이지네이션 부재 → 직원 100명+ 시 전체 로드, 성능 저하
- [HIGH] CSV/Excel 내보내기 없음 → 인사 보고서 작성 시 수동 복사
- [MEDIUM] 정렬 옵션 없음 (입사일·계약만료·비자만료 순 정렬 불가)
- [MEDIUM] 자격증 만료 KPI 카드 없음

---

### `/employees/new` + `/employees/:id/edit`

**충족**
- 기본정보·연락처·직무정보 섹션 분리 ✅
- validation 에러 메시지 (상단 빨간 박스) ✅
- 취소 버튼 ✅
- 필수값 `*` 표시: `name`, `nationality`, `employment_type` (validates presence) — 단, 뷰에서 `*` 시각 표시는 없음

**부분**
- 중복 제출 방지: `data-disable-with` 등 없음. `f.submit`에 로딩 상태 없음.
- 저장 성공 피드백: Rails flash notice로 redirect 후 표시 (뷰 자체에는 없음 — 정상).

**부재**
- 폼 내 필수값 `*` 시각 표시: label에 `*` 없음. 에러 후에야 알게 됨.
- 중복 제출 방지 (Double-submit): `f.submit`에 `data: { turbo_submits_with: "저장 중..." }` 없음.
- 사진/프로필 이미지 업로드: `has_one_attached` 없음 (아바타는 이니셜 기반 컬러).

**발견 갭**
- [MEDIUM] 필수 입력 필드 `*` 시각 표시 없음 → 초기 사용자 혼란
- [MEDIUM] 중복 제출 방지 없음 → 네트워크 지연 시 중복 직원 생성 가능

---

### `/employees/:id` (show)

**충족**
- 수정 버튼 ✅
- 삭제 버튼 + `turbo_confirm` 확인 모달 ✅
- breadcrumb (직원 관리 / 이름) ✅
- KPI 카드 4종 (재직기간, 현장, 비자 D-day, 계약 D-day) ✅
- 탭 URL 직링크 (tab 파라미터) ✅
- 비자/계약/배정/자격증 탭별 빈 상태 CTA ✅
- 비자 갱신 시작 버튼 ✅
- 만료 30일 이내 alert 배너 ✅

**부분**
- 활동/이력 타임라인: 탭별 이력(비자·계약·배정)은 목록으로 있음. 통합 변경이력 타임라인은 없음.
- 관련 항목 링크: 현장 배정 → 프로젝트 상세 링크 없음 (프로젝트명만 텍스트).

**부재**
- 첨부파일 영역: `has_one_attached` / `has_many_attached` 없음. 계약서, 비자 사본 파일 첨부 불가.
- 통합 활동 타임라인: 누가 언제 무엇을 변경했는지 로그 없음.
- 부서 이동 이력 변경점 표시: `employee_assignments`로 현장 이력은 있지만, 부서(department) 변경 이력은 없음.

**발견 갭**
- [CRITICAL] 첨부파일(계약서, 비자 사본) 업로드 불가 → 실무상 원본 서류 디지털 보관 불가
- [HIGH] 통합 변경이력 로그 없음 → 감사/컴플라이언스 추적 불가
- [MEDIUM] 프로젝트 상세 직접 링크 없음

---

### `/employees/:id/visas/new` + `edit`

**충족**
- 비자 종류, 발급국, 번호, 상태, 발급일, 만료일, 메모 필드 ✅
- validation 에러 메시지 ✅
- 취소 버튼 ✅
- 만료일 필수값 `*` 표시 + `required: true` ✅

**부재**
- 비자 사본 파일 첨부 필드 없음
- 갱신 기록(renewal history) 탭: 갱신 시작일/메모만 있고 전체 갱신 이력 관리 없음

**발견 갭**
- [CRITICAL] 비자 사본 파일 첨부 불가 → 실제 비자 문서 관리 불가, 규정 준수 위험
- [MEDIUM] 갱신 이력 관리 없음 (현재는 `renewal_started_at` 단일 필드만)

---

### `/employees/:id/employment_contracts/new` + `edit`

**충족**
- 계약 기간, 기본급, 통화, 지급 주기, 상태, 현장 연결, 메모 ✅
- 시작일 `required: true` ✅
- 취소 버튼 ✅
- 에러 메시지 ✅

**부재**
- 계약서 파일 첨부 없음
- 계약 유형 필드 없음 (정규직 계약서 vs 현장계약서 등 구분)
- 수당/보너스 등 추가 급여 항목 없음

**발견 갭**
- [CRITICAL] 계약서 PDF 첨부 불가 → 전자 계약 관리 불가
- [LOW] 계약 유형 세분화 없음 (single text 필드로 대체 가능하나 분류 어려움)

---

### `/employees/:id/employee_assignments/new` + `edit`

**충족**
- 현장 선택, 역할, 상태, 시작일, 종료일, 메모 ✅
- 시작일/현장 `required` ✅
- 취소 버튼 ✅

**부재**
- 파견 명령서 첨부 없음
- 동일 현장에 여러 역할 동시 배정 지원 없음
- 현장 배정 시 담당 관리자(supervisor) 지정 없음

**발견 갭**
- [MEDIUM] 파견 명령서 문서 첨부 불가
- [LOW] 배정 감독자 지정 필드 없음

---

### `/employees/:id/certifications/new` + `edit`

**충족**
- 자격증명, 발급기관, 취득일, 만료일, 메모 ✅
- 자격증명 `required: true` ✅
- 취소 버튼 ✅

**부재**
- 자격증 파일(이미지/PDF) 첨부 없음
- 자격증 번호 필드 없음
- 갱신 알림 설정(몇 일 전 알림 받을지) 없음

**발견 갭**
- [HIGH] 자격증 사본 첨부 불가 → 자격 요건 증빙 관리 불가
- [MEDIUM] 자격증 번호 필드 없음 (메모로 우회 가능하나 검색 불가)

---

### `/org_chart` (index)

**충족**
- 국가·법인·부서·직원 수 KPI 카드 ✅
- 검색 (Alpine.js 클라이언트 필터링) ✅
- 국가 탭 전환 ✅
- 법인 accordion (접기/펼치기) ✅
- 부서 accordion ✅
- 부서 미배정 직원 별도 섹션 ✅
- DnD 부서 이동 (manager/admin) ✅
- 빈 상태 안내 ✅
- 법인 추가 / 국가 관리 버튼 ✅

**부재**
- 조직도 비주얼 트리 렌더링: 현재는 accordion 목록. 실제 박스-선 계층 그래프 없음.
- 인쇄/내보내기 기능 없음
- 날짜 기준 인원 변동 추이 없음

**발견 갭**
- [MEDIUM] 시각적 조직도(트리 다이어그램) 없음 → 경영진 보고용 조직도 출력 불가
- [LOW] 조직도 인쇄/PDF 내보내기 없음

---

### `/org_chart/companies` (index)

**충족**
- 법인 카드 그리드 ✅
- 부서 수, 직원 수 표시 ✅
- 빈 상태 + CTA ✅
- 법인 추가 버튼 ✅
- breadcrumb ✅

**부재**
- 검색/필터 없음: 법인이 많아질 경우 탐색 불가
- 정렬 없음

**발견 갭**
- [MEDIUM] 법인 목록에 검색 없음 (그룹사 수십 개 시 탐색 불가)

---

### `/org_chart/companies/:id` (show)

**충족**
- 법인 상세 정보 (유형, 직원수, 등록번호, 주소) ✅
- 부서 목록 accordion ✅
- 부서별 직원 chip ✅
- 수정 버튼 ✅
- 하위 부서 추가 ✅

**부재**
- 법인 삭제 버튼 없음 (routes에도 destroy 없음)
- 법인 비활성화 토글은 edit 폼에만 있음 (show에서 직접 불가)
- 법인 소속 직원 전체 목록 페이지 없음 (부서별 chip으로만 확인)

**발견 갭**
- [HIGH] 법인 삭제 불가 (routes 미지원) → 잘못 생성된 법인 정리 불가
- [LOW] 법인 직원 전체 목록 뷰 없음

---

### `/org_chart/countries` (index)

**충족**
- 국가 테이블 (이름, 지역, 법인 수) ✅
- 수정, 삭제 링크 ✅ (삭제 confirm 포함)
- 빈 상태 ✅
- 국가 추가 버튼 ✅

**부재**
- 법인이 있는 국가를 삭제할 때 cascade 경고 없음 (루비 validates로 막혀 있을 수 있으나 뷰에 안내 없음)

**발견 갭**
- [MEDIUM] 연결 데이터 있는 항목 삭제 시 사전 경고 메시지 없음

---

### `/org_chart/countries/:id` (show)

**충족**
- KPI 카드 (법인 수, 직원 수, 부서 수) ✅
- 법인 목록 ✅
- breadcrumb ✅

**부재**
- 비자 만료 임박 직원 현황 없음 (국가별 비자 리스크 overview)
- 국가 삭제 버튼 없음 (show에서 접근 불가, countries/index에서만)

**발견 갭**
- [MEDIUM] 국가 단위 비자 만료 현황 없음 → 지역 HR 매니저가 국가별 리스크 파악 불가

---

### 인라인 관리: `/employees/departments`, `/employees/job_titles`

**충족**
- 직원 폼 내 모달로 부서/직책 추가·삭제 ✅
- 회사별 부서 추가 가능 ✅

**부재**
- 독립 관리 화면 없음: bulk 추가, 정렬 순서 변경, 설명 추가 등은 폼 외부에서 불가
- 부서 이동 이력 (직원이 어느 부서에서 어느 부서로) 없음

**발견 갭**
- [HIGH] 부서 이동 이력 없음 → 직원 경력 경로 추적 불가

---

## 4. 우선순위 액션 항목 (Top 10)

| # | 우선순위 | 화면 | 갭 | 임팩트 | 추정 작업시간 |
|---|------|------|------|------|------|
| 1 | CRITICAL | 직원 상세 / 비자 폼 / 계약 폼 / 자격증 폼 | 첨부파일(계약서·비자·자격증 사본) 업로드 | 규정 준수·원본 보관 불가 | 6~8h |
| 2 | CRITICAL | 비자 폼 | 비자 사본 파일 첨부 | 갱신 담당자가 원본 확인 불가 | (1번 포함) |
| 3 | CRITICAL | 계약 폼 | 계약서 PDF 첨부 | 전자 계약 이력 없음 | (1번 포함) |
| 4 | CRITICAL | 직원 상세 | 변경이력(감사 로그) 타임라인 | 컴플라이언스·HR 감사 시 추적 불가 | 4~6h |
| 5 | CRITICAL | 자격증 폼 | 자격증 사본 첨부 | 현장 자격 증빙 불가 | (1번 포함) |
| 6 | HIGH | 직원 index | 페이지네이션 (pagy 설치됨, 미적용) | 100명+ 시 성능 저하 | 1~2h |
| 7 | HIGH | 직원 index | CSV/Excel 내보내기 | 인사 보고서 수동 작업 | 3~4h |
| 8 | HIGH | org_chart/companies/:id | 법인 삭제 기능 | 잘못 생성된 법인 정리 불가 | 1~2h |
| 9 | HIGH | 직원 전체 | 부서 이동 이력 | 직원 경력 경로 파악 불가 | 4~6h |
| 10 | HIGH | 자격증 폼 | 자격증 사본 첨부 (별도 강조) | 현장 투입 요건 증빙 | (1번 포함) |

---

## 5. 인사 도메인 특화 누락 (10개 항목)

| 항목 | 현황 | 등급 |
|------|------|------|
| 비자 만료 알림 | ✅ 60일 배너 + 자동 갱신 시작 Job (HrExpiryNotificationJob) | 충족 |
| 계약 만료 추적 | ✅ 30일 KPI 카드 + 상세 D-day | 충족 |
| 재직중/퇴직 필터 | ✅ 기본 재직중, `show_inactive` 토글 | 충족 |
| 부서 이동 이력 | ❌ department_id 변경 이력 없음 (employee_assignments는 현장 배정 전용) | HIGH |
| 조직도 시각화 | △ accordion 목록 수준. 박스-선 계층 트리 없음 | MEDIUM |
| 신규 입사 온보딩 체크리스트 | ❌ 없음. 입사일 입력만 존재 | HIGH |
| 휴가/근태 모듈 | ❌ 없음. 메뉴 자체 없음 | CRITICAL (도메인 공백) |
| 인사평가/리뷰 모듈 | ❌ 없음 | CRITICAL (도메인 공백) |
| 급여/연봉 모듈 | △ 계약서에 기본급/통화/주기 기록 가능. 별도 급여 대장 없음 | HIGH |
| 조직도 vs 부서 관리 분리 | △ org_chart(시각화) vs employees/departments(인라인 CRUD) 2원화. 일관성 낮음 | MEDIUM |

---

## 6. 권장 다음 작업

우선순위 순으로:

1. **첨부파일 인프라 (P0)**: `Employee`, `Visa`, `EmploymentContract`, `Certification` 모델에 `has_many_attached :documents` 추가 + 각 폼에 파일 업로드 필드 + 직원 상세 탭에 파일 목록
2. **변경이력 로그 (P0)**: `PaperTrail` gem 또는 커스텀 `HrActivityLog` 테이블로 직원 정보 변경 추적 + 직원 상세에 타임라인 탭 추가
3. **페이지네이션 (P1)**: `EmployeesController#index`에 `pagy` 적용 (gem 이미 설치됨)
4. **CSV 내보내기 (P1)**: 직원 index에 Excel/CSV 다운로드 버튼
5. **온보딩 체크리스트 (P1)**: 신규 직원 등록 시 표준 온보딩 항목(비자 등록, 계약 등록, 배정 등록) 자동 생성
6. **부서 이동 이력 (P2)**: `DepartmentHistory` 테이블 또는 `before_save` 훅으로 `department_id` 변경 추적
7. **법인 삭제 (P2)**: `org_chart/companies` routes에 `:destroy` 추가 + 직원 있는 경우 블록
8. **조직도 시각 트리 (P3)**: D3.js 또는 OrgChart.js 기반 트리 시각화 (경영진 보고용)
