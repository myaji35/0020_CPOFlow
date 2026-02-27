# Plan: order-form-autocomplete

## Feature Overview
오더 생성/수정 폼의 발주처(Client), 공급사(Supplier), 현장/프로젝트(Project) 필드를
`<select>` 드롭다운에서 **Stimulus + AJAX 자동완성 검색 위젯**으로 교체한다.

현재 Client는 ~수백 건, Supplier·Project는 수십~수백 건이 DB에 존재하며,
전체 목록을 한 번에 렌더링하면 폼 로딩이 느리고 UX가 불편하다.

## Problem Statement
- 현재: `f.select` — 전체 목록을 서버에서 렌더링 후 `<option>`으로 출력
- 문제 1: Client/Supplier가 늘어날수록 폼 응답 속도 저하
- 문제 2: 텍스트 검색 불가 — 스크롤로 찾아야 함
- 문제 3: 선택된 항목의 부가 정보(코드, 국가, 산업) 확인 불가

## Goals
1. 텍스트 입력 → 실시간 AJAX 검색 → 드롭다운 목록 → 클릭 선택
2. 선택 후 배지 형태로 선택된 항목 표시 (이름 + 코드)
3. 선택 해제(X) 가능
4. 숨김 `<input type="hidden">` 에 ID 값 저장 → 폼 submit 정상 작동
5. 기존 편집 시 현재 값 pre-populate

## Scope

### In Scope
- `_form.html.erb` — client_id, supplier_id, project_id 3개 필드 교체
- `AutocompleteController` (Stimulus) — 공통 1개 컨트롤러로 3필드 재사용
- AJAX 검색 엔드포인트 3개:
  - `GET /clients/search?q=...` → JSON
  - `GET /suppliers/search?q=...` → JSON
  - `GET /projects/search?q=...` → JSON
- 키보드 네비게이션 (↑↓ Enter Escape)
- 빈 결과 메시지

### Out of Scope
- 멀티 선택 (1:1 관계 유지)
- 새 항목 즉석 생성 (별도 페이지에서 생성 후 선택)
- 외부 라이브러리 설치 (순수 Stimulus + fetch API)

## Technical Approach

### 1. Search Endpoints
각 컨트롤러에 `search` 액션 추가 (collection route):
```
GET /clients/search?q=sika  →  JSON [{ id, name, code, country }]
GET /suppliers/search?q=sika → JSON [{ id, name, code, industry }]
GET /projects/search?q=bara  → JSON [{ id, name, client_name, status }]
```
- `q` 파라미터: `ILIKE %q%` (이름 검색, 최대 10건)
- 인증 필요 (`before_action :authenticate_user!`)
- 응답 형식: `format.json`

### 2. Stimulus Controller (`autocomplete_controller.js`)
Values:
- `url` — 검색 엔드포인트 URL
- `placeholder` — input placeholder 텍스트

Targets:
- `input` — 텍스트 검색 input
- `hidden` — 실제 ID를 담는 hidden input (폼 제출용)
- `dropdown` — 검색 결과 목록
- `badge` — 선택된 항목 표시 배지

동작:
1. `input` 타이핑 → debounce 300ms → fetch 검색
2. 결과 렌더링 → 키보드·마우스로 선택
3. 선택 시: hidden에 ID 저장, badge 표시, input 숨김, dropdown 닫기
4. badge X 클릭: hidden 초기화, input 재노출

### 3. ERB 폼 수정
`f.select` 3개를 `autocomplete` data-controller 위젯으로 교체.
기존 `hidden_field`는 Stimulus가 동적으로 관리.

## Acceptance Criteria
- [ ] 발주처 텍스트 입력 시 0.3초 후 목록 표시
- [ ] 10건 이하 결과 표시, 초과 시 "더 구체적으로 입력하세요" 메시지
- [ ] 항목 선택 후 배지로 표시 + X로 해제 가능
- [ ] 폼 제출 시 hidden input의 ID값이 정상 전송됨
- [ ] 기존 오더 편집 시 현재 client/supplier/project 미리 표시됨
- [ ] 키보드만으로 전체 조작 가능 (접근성)
- [ ] 다크모드 대응

## Implementation Order
1. routes.rb — search 컬렉션 라우트 3개 추가
2. clients/suppliers/projects 컨트롤러 — search 액션 추가
3. `autocomplete_controller.js` — Stimulus 컨트롤러 작성
4. `_form.html.erb` — 3개 select → autocomplete 위젯 교체
5. smoke test + rubocop
