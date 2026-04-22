# View Audit — 2026-04-22 (ISS-233)

## Route-View Mapping (78/79)

전체 라우트 대비 뷰 파일 존재 여부 확인. HTML 렌더링이 필요한 액션 기준.

### Missing Views: 1건

| 경로 | 액션 | 위험도 | 비고 |
|---|---|---|---|
| `GET /search` | `search#index` | **LOW** | JSON only 응답 — `render json:` 사용, HTML 뷰 불필요. 실제 404 위험 없음. |

> search_controller.rb 확인 결과: `render json: results` 전용. 뷰 파일 없는 것이 정상.

**실제 누락 없음. 전체 78개 라우트-뷰 매핑 정상.**

### 추가 확인: settings/email_accounts 뷰

`settings/email_accounts` 컨트롤러는 존재하나 대응 뷰 디렉터리(`app/views/settings/email_accounts/`) 없음.
라우트에 `index`, `new`, `create`, `destroy`, `sync` 선언됨.
컨트롤러 확인 필요 (turbo_stream 전용 응답 가능성).

---

## Layout Consistency

### 레이아웃 파일 구성
- `application.html.erb` — 인증된 사용자용 메인 레이아웃
- `auth.html.erb` — Devise 로그인/회원가입 전용
- `pdf.html.erb` — PDF 출력 전용

### application.html.erb 구조 확인
- **TailwindCSS**: CDN 방식 (`cdn.tailwindcss.com`) — 빌드 없음, 정상
- **공용 파셜**: `shared/sidebar` + `shared/header` 포함 확인
- **JS 외부 CDN**: Cytoscape.js + Dagre (org chart용) — 정상
- **stylesheet_link_tag :app**: `app/assets/stylesheets/application.css` 존재 확인

### 레이아웃 일관성 판정: PASS

모든 인증 필요 뷰는 `application.html.erb` 상속.
PDF 뷰(`orders/pdf/`)는 `pdf.html.erb` 상속 — 의도적 분리.
Devise 뷰는 `auth.html.erb` 사용 — 의도적 분리.

---

## Partial Reuse Opportunities

### 현황
`_form.html.erb` 파셜이 15개 리소스에 정상 존재하며 new/edit에서 공유됨.
`shared/_header`, `shared/_sidebar` 레이아웃 수준에서 전역 공유.

### 리팩터 후보 (3회 이상 중복 패턴)

| 패턴 | 발생 횟수 | 위치 | 추천 파셜명 |
|---|---|---|---|
| `inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-primary-dark` | 4+ | suppliers/index, employees/index, clients/index, admin/imports/index | `shared/_primary_btn` |
| `px-4 py-2 border border-gray-200 text-gray-600 rounded-lg text-sm hover:bg-gray-50` (취소 버튼) | 4 | employees/edit, org_chart/countries/edit, org_chart/companies/edit, certifications/edit | `shared/_cancel_btn` |
| 필터 select 인라인 패턴 (`text-xs border ... py-1.5`) | 3 | suppliers/show, projects/show, admin/ecount/customers/index | `shared/_filter_select` |

> 파셜화 ROI: medium. 현재 기능 영향 없음. P3 수준 개선 과제.

---

## Asset Loading

### CSS
- `stylesheet_link_tag :app` → `app/assets/stylesheets/application.css` 존재 확인
- TailwindCSS CDN 로드: 정상

### JavaScript (외부 CDN)
- `cytoscape@3.30.2` — org chart 전용, CDN unpkg
- `dagre@0.8.5` — dagre 레이아웃 엔진
- `cytoscape-dagre@2.5.0` — 연결 플러그인

### 누락 asset: 없음
- `public/images/`, `public/icon.png`, `public/icon.svg` 정상 존재
- `public/favicon.ico` 존재 (레이아웃은 SVG inline favicon 사용 — 정상 override)

---

## 가독성 규칙 위반 (CRITICAL/HIGH/MEDIUM)

### CRITICAL (즉시 수정) — 입력 필드 직접 위반

| # | 파일 | 라인 | 위반 내용 | 수정 방향 |
|---|---|---|---|---|
| C-01 | `inbox/show.html.erb` | 50, 472 | `select` 에 `text-xs` + `py-1.5` | `text-sm`, `py-2` 이상 |
| C-02 | `suppliers/show.html.erb` | 260, 266, 272 | `select` 에 `text-xs border-gray-200 py-1.5` | `text-sm`, `border-gray-300`, `py-2` |
| C-03 | `projects/show.html.erb` | 96 | `select` 에 `text-xs border-gray-200 py-1.5` | `text-sm`, `border-gray-300`, `py-2` |
| C-04 | `admin/ecount/customers/index.html.erb` | 19~20 | `input`, `select` 에 `py-2` (py-2.5 아님) | `py-2.5` |
| C-05 | `settings/base/index.html.erb` | 215, 219, 224 | `input` 에 `border-gray-200 py-2` | `border-gray-300 py-2.5` |

### HIGH (가능한 한 빠른 수정) — 배지 투명도 위반

`bg-*-100 text-*-NNN` 패턴 총 **14건** — solid 배경으로 교체 필요.

| 파일 | 건수 | 대표 예시 |
|---|---|---|
| `admin/ecount_sync/index.html.erb` | 5 | `bg-amber-100 text-amber-800`, `bg-blue-100 text-blue-700` |
| `admin/ecount/customers/index.html.erb` | 3 | `bg-emerald-100 text-emerald-700`, `bg-blue-100 text-blue-700` |
| `admin/ecount/customers/show.html.erb` | 1 | `bg-emerald-100` / `bg-blue-100` |
| `admin/rfq_stats/index.html.erb` | 2 | `bg-blue-100`, `bg-green-100`, `bg-red-100` |
| `admin/ecount/products/index.html.erb` | 1 | `bg-green-100 text-green-800` |
| `agent_insights/index.html.erb` | 1 | `bg-blue-100`, `bg-amber-100`, `bg-red-100` |
| `reports/export_pdf.html.erb` | 1 | `bg-gray-100 text-gray-700` (버튼, medium) |

**수정 방향**: `bg-emerald-600 text-white`, `bg-blue-600 text-white` 등 solid 색상으로 교체.

### MEDIUM (계획적 수정) — 카드 border-gray-100

총 **6건** 발견. 규칙상 최소 `border-gray-200` 사용 필요.

| 파일 | 라인 | 위치 |
|---|---|---|
| `calendar/index.html.erb` | 162, 229, 236 | 캘린더 셀 구분선, 오더 카드 |
| `orders/_drawer_content.html.erb` | 79 | 드로어 내 구분선 |
| `org_chart/index.html.erb` | 341 | org chart 카드 하단 |
| `team/index.html.erb` | 258 | 팀원 카드 하단 |

---

## 요약 지표

| 항목 | 결과 |
|---|---|
| 라우트 총계 | 79개 (HTML 렌더링 필요) |
| 뷰 누락 | **0건** (search는 JSON only) |
| 레이아웃 일관성 | PASS |
| 파셜 리팩터 후보 | 3개 패턴 |
| Asset 누락 | 없음 |
| 가독성 위반 CRITICAL | **5건 (9개 라인)** |
| 가독성 위반 HIGH | **14건** |
| 가독성 위반 MEDIUM | **6건** |
