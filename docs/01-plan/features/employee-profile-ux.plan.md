# Plan: employee-profile-ux

## 개요
직원 상세(show) 페이지와 목록(index) 페이지의 UX를 개선하여,
HR 담당자가 직원 프로필을 한눈에 파악하고 빠르게 액션을 취할 수 있도록 한다.

- **Feature**: employee-profile-ux
- **Priority**: High
- **Started**: 2026-03-01

---

## 현재 상태 (As-Is)

### show 페이지 문제점
1. **아바타 없음** — 이름 이니셜 아바타조차 없어 인물 식별이 어렵다
2. **연락처 액션 없음** — 전화번호/이메일이 텍스트로만 표시, 클릭 불가
3. **탭 URL 직링크 없음** — 특정 탭(비자, 계약 등) 공유 불가
4. **인라인 추가 없음** — 비자/계약/배정 추가 시 별도 페이지로 이동
5. **빈 상태(empty state) 단조** — 단순 텍스트, 빠른 추가 CTA 없음
6. **KPI 카드 개선 여지** — 재직기간이 "일"로만 표시 (연/월 단위 미표현)

### index 페이지 문제점
1. **아바타 컬럼 없음** — 이름만 나열, 시각적 식별 어려움
2. **부서/직책 필터 없음** — 고용형태 필터만 존재
3. **Quick Action 없음** — 행 호버 시 빠른 액션 버튼 없음
4. **직책(job_title) 컬럼 없음** — 목록에서 직책 확인 불가

---

## 목표 (To-Be)

### FR-01: 직원 아바타 (이니셜 + 국적 배지)
- show 헤더: 64px 원형 아바타 (이니셜, 국적별 배경색)
- index 테이블: 32px 미니 아바타

### FR-02: 탭 URL 직링크 (Alpine.js → URL hash)
- `?tab=visas`, `?tab=contracts`, `?tab=assignments`, `?tab=certs`
- 페이지 로드 시 URL params로 탭 초기화
- 탭 클릭 시 URL hash 업데이트 (pushState)

### FR-03: 연락처 원클릭 액션
- 전화번호: `tel:` 링크 + 전화 아이콘
- 이메일: `mailto:` 링크 + 메일 아이콘
- WhatsApp: `https://wa.me/` 딥링크 (phone 있을 때)

### FR-04: 빈 상태(Empty State) 개선
- 각 탭 빈 상태에 CTA 버튼 포함
- "비자가 없습니다. [+ 비자 추가]" 형태

### FR-05: KPI 카드 재직기간 포맷 개선
- "365일" → "1년 0개월" 형태로 표시
- 모델 helper 메서드 추가: `tenure_label`

### FR-06: index 필터 — 부서/직책 추가
- 부서 select 필터 추가
- 직책 select 필터 추가 (job_title 컬럼 기반)

### FR-07: index 테이블 — 직책 컬럼 추가
- 국적/부서 셀에 직책(job_title) 함께 표시

### FR-08: index 행 Quick Action
- 행 호버 시 [상세 / 수정] 버튼 표시 (현재 "상세"만 있음)

---

## 범위 제외 (Out of Scope)
- 프로필 사진 업로드 (파일 스토리지 별도 피처)
- 급여명세서 PDF 출력
- 인라인 편집 (별도 피처)

---

## 구현 파일 목록 (예상)

| 파일 | 변경 유형 | 설명 |
|------|---------|------|
| `app/views/employees/show.html.erb` | 수정 | 아바타, 탭 URL, 연락처 액션, 빈 상태 |
| `app/views/employees/index.html.erb` | 수정 | 아바타, 직책 컬럼, 필터, Quick Action |
| `app/models/employee.rb` | 수정 | `tenure_label`, `avatar_color` helper |
| `app/controllers/employees_controller.rb` | 수정 | 부서/직책 필터 파라미터 추가 |

---

## 성공 기준
- Match Rate ≥ 90% (gap-detector 기준)
- 8개 FR 모두 구현
- Dark mode 완전 지원
- 기존 기능 회귀 없음
