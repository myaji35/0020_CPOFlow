# Plan: client-supplier-management

> 발주처(Client) · 거래처(Supplier) · 현장(Project) 심층 관리 고도화
> CPOFlow Phase 4 — 거래내역 추적 관리 완성

---

## 배경 및 목적

### 현재 상태 (AS-IS)
- Client/Supplier/Project 기본 CRUD 구현 완료
- 각 엔티티에 연결된 Order 목록 조회 가능 (show 페이지 탭 형태)
- eCount 코드(ecount_code) 기반 데이터 이관 완료
- 경영 리포트에 발주처/거래처 Top 10 표시 중

### 부족한 부분 (GAP)
1. **사이드바 네비게이션 링크 없음** — /clients, /suppliers, /projects 접근 경로 미노출
2. **거래처(Supplier) 성과 분석 부족** — 납기준수율·리드타임·품목별 공급 이력 통계 미흡
3. **발주처(Client) 프로젝트 연결 UI 부족** — Client → Project → Order 드릴다운 플로우 없음
4. **Order 생성 시 Client/Supplier/Project 선택 UX 미흡** — 현재 텍스트 입력, 검색 선택 없음
5. **Supplier 평가 카드 미구현** — 납품 실적 기반 A~D 등급 시각화 없음
6. **거래처 비교 기능 없음** — 동종 거래처 간 성과 비교 불가
7. **Client/Supplier 인쇄 / 내보내기 없음** — 외부 공유 불가

### 목표 (TO-BE)
- 사이드바에 Client/Supplier/Project 메뉴 추가
- 발주처·거래처 상세 페이지 고도화 (성과 분석 + 시각화)
- Order 생성 폼에서 Client/Supplier/Project 검색 선택(Select2 스타일) 연동
- Supplier 성과 등급 카드 + 납품 이력 차트
- Client 리스크 분석 강화

---

## 기능 요구사항 (FR)

### FR-01: 사이드바 네비게이션 추가
- 사이드바에 "발주처", "거래처", "현장" 아이콘+링크 추가
- 현재 페이지 활성 상태 강조
- 메뉴 권한 설정(MenuPermission) 반영

### FR-02: 발주처(Client) 목록 고도화
- 업종별 컬러 배지 (기존 존재)
- 리스크 등급(A~D) 컬럼 추가
- 총 거래금액 정렬 기능
- 페이지네이션 추가 (20개/페이지)

### FR-03: 발주처(Client) 상세 고도화
- 프로젝트 탭: 예산 집행률 미니 바차트 추가
- 거래이력 탭: 월별 발주 추이 미니 차트(Chart.js)
- 담당자 탭: 언어 배지, 연락처 클릭 시 복사
- 계약 정보 섹션: 결제조건, 통화, 신용등급, 계약시작일 표시

### FR-04: 거래처(Supplier) 목록 고도화
- 성과등급(A~D) 컬럼 추가
- 납품품목 수 컬럼 추가
- 리드타임 컬럼 추가
- 페이지네이션 추가

### FR-05: 거래처(Supplier) 상세 고도화
- 성과 분석 섹션: 납기준수율 게이지, 평균 리드타임, 총 공급금액
- 납품 이력 탭: 월별 납품 추이 Chart.js 선 그래프
- 품목별 공급 실적: 품목명 + 공급 횟수 + 총 금액
- 비교 배지: 동종 업계 평균 대비 납기준수율

### FR-06: Order 폼 선택 UX 개선
- Client/Supplier/Project 필드: input 입력 → AJAX 검색 선택 (Stimulus + Turbo Stream)
- 선택 후 이름 표시 + hidden input으로 ID 전송
- 빠른 선택을 위한 최근 사용 목록 제안

### FR-07: 현장(Project) 목록 고도화
- 예산 집행률 프로그레스 바 컬럼 추가
- 상태별 필터 탭 (계획/진행중/완료/중단)
- 활성 현장 우선 정렬

### FR-08: 현장(Project) 상세 고도화
- 예산 현황 섹션: 총 예산, 집행액, 잔여 예산, 집행률 게이지
- 오더 목록 탭: 납기일 기준 정렬 + 상태 배지
- 배정 직원 탭: 역할/기간 표시

---

## 구현 우선순위

| 우선순위 | FR | 설명 | 난이도 |
|---------|-----|------|--------|
| P1 | FR-01 | 사이드바 네비게이션 추가 | Low |
| P1 | FR-03 | Client 상세 고도화 | Medium |
| P1 | FR-05 | Supplier 상세 고도화 | Medium |
| P2 | FR-02 | Client 목록 고도화 | Low |
| P2 | FR-04 | Supplier 목록 고도화 | Low |
| P2 | FR-07 | Project 목록 고도화 | Low |
| P3 | FR-06 | Order 폼 선택 UX | High |
| P3 | FR-08 | Project 상세 고도화 | Medium |

---

## 영향 범위

### 수정 파일
- `app/views/layouts/application.html.erb` — 사이드바 네비 추가
- `app/views/clients/index.html.erb` — 목록 고도화
- `app/views/clients/show.html.erb` — 상세 고도화
- `app/views/suppliers/index.html.erb` — 목록 고도화
- `app/views/suppliers/show.html.erb` — 상세 고도화
- `app/views/projects/index.html.erb` — 목록 고도화
- `app/views/projects/show.html.erb` — 상세 고도화
- `app/views/orders/_form.html.erb` — 선택 UX 개선

### 수정 컨트롤러
- `app/controllers/clients_controller.rb` — 페이지네이션, 정렬
- `app/controllers/suppliers_controller.rb` — 페이지네이션, 통계 추가

### 새 파일 (필요 시)
- `app/javascript/controllers/search_select_controller.js` — FR-06 Stimulus 컨트롤러

### DB 변경
- 없음 (기존 스키마로 충분)

---

## 비기능 요구사항

- 모든 페이지 다크모드 지원
- Chart.js 4.4.0 CDN 사용 (경영 리포트와 동일)
- 라인 아이콘 사용 (stroke-width: 2)
- 모바일 반응형 (sm: 브레이크포인트)
- 페이지네이션 20개/페이지

---

## 제외 범위

- Supplier 삭제 기능 (발주 이력 보존 정책 유지)
- Client/Supplier 간 비교 뷰 (별도 피처로 분리)
- 거래처 평가 설문/피드백 시스템

---

## 완료 기준

- [ ] 사이드바에서 Client/Supplier/Project 접근 가능
- [ ] Client 상세에 거래이력 Chart.js 차트 표시
- [ ] Supplier 상세에 납품 실적 Chart.js 차트 표시
- [ ] Project 상세에 예산 집행률 게이지 표시
- [ ] Order 폼에서 Client/Supplier/Project 검색 선택 가능
- [ ] 모든 목록 페이지 페이지네이션 동작
- [ ] 다크모드 정상 작동

---

*작성일: 2026-02-28*
*Phase: Plan*
