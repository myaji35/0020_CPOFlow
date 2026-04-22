# Journey Validation — 2026-04-22

**대상**: CPOFlow (조달/발주 9단계 워크플로우 SaaS)
**평가 역할**: admin / manager / member / viewer
**평가 터치포인트**: login, dashboard, kanban, order detail, settings
**평가 기준**: brand-dna.json emotional_tone [Trustworthy, Efficient, Composed, Enterprise-grade]

---

## Role Coverage: 6/10

### 평가 근거

**PASS 항목**

- 로그인 후 단일 랜딩: `config/routes.rb:10` — `authenticated :user { root to: "dashboard#index" }`. 모든 역할이 `/dashboard`로 착지. 일관성 O.
- 역할 구분 사이드바: `app/views/shared/_sidebar.html.erb:62` — `if current_user.manager? || current_user.admin?` 조건으로 "관리" 그룹(경영 리포트/eCount/메뉴권한)이 viewer/member에게 숨겨짐.
- Admin 전용 섹션: `settings/base/index.html.erb:287` — Google Sheets 연동, 칸반 보드 관리, 메뉴권한 관리가 `current_user.admin?`으로 격리.
- 권한 기반 CTA: `orders/index.html.erb:10` — `can_create?("orders")` true일 때만 "주문 추가" 버튼 노출.
- Kanban 읽기전용 배너: `kanban/index.html.erb:7-13` — viewer/member에게 "읽기 전용 모드 — 카드 이동/수정은 manager 이상 권한이 필요합니다." 즉시 표시.
- 오더 상세 수정 버튼: `orders/show.html.erb:31` — `can_update?("orders")` 기반 조건부 렌더.

**GAP 항목**

- **역할별 차별화된 랜딩 없음 (P1)**: admin은 직원 관리·보고서 중심, viewer는 조회만 가능한데 모두 동일한 `/dashboard`로 이동. viewer 첫 화면에서 "나는 뭘 할 수 있나?" 신호가 없음.
- **viewer 역할 온보딩 메시지 없음 (P1)**: viewer 로그인 시 읽기전용임을 대시보드에서 안내하는 배너/안내문 없음. kanban에서는 있음(`kanban/index.html.erb:7-13`)이지만 대시보드 도착 시점에 없음.
- **after_sign_in_path_for 미오버라이드**: `users/sessions_controller.rb` — `layout "auth"` 만 선언. 역할별 리디렉션 로직 없음. admin은 `/admin/...` 직행이 더 효율적이나 미구현.
- **에러 메시지 언어 혼재**: `application_controller.rb:31` — `redirect_to root_path, alert: "Access denied."` 영어. 다른 곳은 한국어. 일관성 깨짐.

---

## Impact: 7/10

### 평가 근거

**PASS 항목**

- 긴급 조치 배너: `dashboard/index.html.erb:3-24` — `critical_count > 0`이면 붉은 배너 즉시 표시. "즉시 조치 필요 — N건" + "확인하기" CTA. 0.5초 이내 가시성 O.
- KPI 카드 존재: `dashboard_controller.rb:7-9` — `@total_active`, `@overdue_count`, `@urgent_count`, `@delivered_this_month` 4개 지표 즉시 노출.
- 이번 주/다음 주 납기 위젯: `dashboard/index.html.erb:78-` — D-day 색 코딩(D+N → 빨강, D-1 → 노랑, 이후 → 기본) 적용.
- 신규 발주 CTA: `dashboard/index.html.erb:33-39` — 우측 상단 primary CTA `신규 발주` 버튼. `primary_action_per_screen: MUST_EXIST` 준수.
- 보드별 요약 카드: `dashboard/index.html.erb:61-76` — 복수 보드일 때 grid로 각 보드 총/신규/진행/완료 표시. 클릭하면 해당 보드 kanban 이동.
- Inbox 미처리 카운트: `shared/_sidebar.html.erb:37-40` — 사이드바에 RFQ 미처리 건수 뱃지 상시 표시.

**GAP 항목**

- **내 담당 발주 즉시 조회 미흡 (P1)**: 대시보드에서 "내가 담당한 오늘 처리해야 할 항목" 필터링 뷰가 없음. `@urgent_orders`는 전체 기준(admin view). member/viewer는 자신의 할 일 파악 불가.
- **KPI 카드 미표시 조건**: 데이터가 0일 때 KPI 카드가 그냥 0을 보여줌. "아직 발주가 없습니다 — 신규 발주 시작" 형태의 유도 없음.
- **orders/index.html.erb KPI**: `orders/index.html.erb:18-60` — 총건수/진행중/완료/연체 4개 KPI 있으나 클릭 시 필터 드릴다운 미지원.

---

## Onboarding: 4/10

### 평가 근거

**PASS 항목**

- 빈 칸반 칼럼 empty-state: `kanban/index.html.erb:268-269` — `empty-state` div 존재. 단순 "텍스트 없음" 표시.
- 빈 태스크 state: `orders/_drawer_content.html.erb:414` — tasks.empty? 조건 분기 존재(내용은 미확인이나 분기는 있음).
- 회원가입 링크 존재: `devise/sessions/new.html.erb:67-70` — "계정이 없으신가요? 회원가입" 링크.

**GAP 항목**

- **신규 사용자 가이드 완전 부재 (P0)**: 첫 로그인 후 "CPOFlow를 시작하는 방법" 안내 없음. 튜토리얼, 가이드 투어, 체크리스트 없음. 전체 뷰 디렉토리에서 `온보딩`, `tutorial`, `getting_started` 파일 0개.
- **빈 대시보드 empty state 미존재 (P1)**: `dashboard_controller.rb` — 데이터가 전혀 없을 때(`@total_active == 0`) 특별 처리 없음. 신규 설치 직후 대시보드는 의미없는 0값 나열.
- **빈 칸반 empty-state 메시지 비친절 (P1)**: `kanban/index.html.erb:269` — 단순 `empty-state flex items-center justify-center text-xs text-gray-500` div. 구체적 안내문 없음. "아직 발주가 없습니다. 신규 발주 버튼을 눌러 시작하세요." 형태의 액션 유도 없음.
- **설정 페이지 최초 진입 가이드 없음 (P1)**: 신규 사용자가 Gmail 연동, API 키 설정을 해야 함을 알 수 없음. Settings 상단에 "시작 전 필수 설정" 체크리스트 없음.
- **역할 설명 없음 (P1)**: viewer/member 첫 로그인 시 자신의 역할(읽기전용, 작성가능 등)을 알 수 없음. 역할 안내 토스트/배너 없음.

---

## Guidance: 6/10

### 평가 근거

**PASS 항목**

- 폼 에러 메시지: `orders/_form.html.erb:4-8` — `order.errors.any?`일 때 붉은 박스로 `full_messages` 표시.
- Flash 메시지 시스템: `settings/base/index.html.erb:11-22` — notice(초록)/alert(붉은) 양식 일관.
- 권한 오류 피드백: `kanban/index.html.erb:7-13` — viewer에게 잠금 아이콘 + 텍스트 설명으로 읽기전용 이유 명시.
- 로그인 폼 UX: `devise/sessions/new.html.erb` — 이메일 autofocus, placeholder, remember_me, 비밀번호 찾기 링크 모두 구현.
- Turbo confirm 적용: `settings/base/index.html.erb:357` — 위험 작업에 `turbo_confirm` 확인 다이얼로그.
- D-day 색 코딩: `dashboard/index.html.erb:104` — D+N(초과) → 빨강, D-1 → 노랑, 정상 → 기본. 시각 신호 명확.
- 상태 배지 색상: `settings/base/index.html.erb:36,105` — 연결됨(초록 solid)/미설정(회색) 배지. solid 배경 준수.

**GAP 항목**

- **에러 메시지 언어 혼재 (P1)**: `application_controller.rb:31` — `"Access denied."` 영어. `reports_controller.rb:259` — `"접근 권한이 없습니다."` 한국어. 동일 기능(접근 거부)에 2가지 언어 혼용.
- **폼 제출 로딩 상태 없음 (P1)**: `orders/_form.html.erb` — 저장 버튼 클릭 후 로딩 스피너/비활성화 없음. 네트워크 지연 시 중복 제출 위험.
- **설정 폼 border-gray-200 → border-gray-300 미준수 (minor)**: `settings/base/index.html.erb:120` — `border-gray-200` 사용. SLDS 규칙 위반(최소 `border-gray-300`).
- **이모지 사용 (minor)**: `settings/base/index.html.erb:146-149` — 알림 스케줄에 🔵🟡🟠🔴 이모지. brand-dna.json `anti_patterns` 및 CLAUDE.md "Feather outline만" 규칙 위반.
- **취소 버튼 없음 (P1)**: 주문 신규 생성 폼(`orders/new.html.erb`)에서 취소 버튼 미확인. 사용자가 폼을 닫으려면 브라우저 뒤로가기에 의존.
- **성공 피드백 일관성**: 일부 PATCH 액션 후 flash notice 있으나 Turbo 요청의 경우 페이지 이동 없이 시각 피드백 없는 경우 존재.

---

## Total: 23/40

| 차원 | 점수 | 최대 |
|---|---|---|
| 역할 커버리지 | 6 | 10 |
| 인팩트 (Impact) | 7 | 10 |
| 온보딩 | 4 | 10 |
| 안내 품질 (Guidance) | 6 | 10 |
| **합계** | **23** | **40** |

---

## Critical Issues (P0)

1. **신규 사용자 가이드 완전 부재** — 첫 로그인 후 시스템 사용법 안내 없음. 가장 먼저 해야 할 일(Gmail 연동, 첫 발주 생성)을 모름. 관련 파일: 없음(신규 생성 필요).

---

## Major Issues (P1)

2. **viewer 역할 대시보드 진입 시 읽기전용 안내 없음** — kanban에는 배너 있으나(`kanban/index.html.erb:7`) 대시보드에는 없음.
3. **내 담당 발주 즉시 조회 부재** — member/viewer가 "내 오늘 할 일"을 한눈에 파악할 수 없음. `dashboard_controller.rb`에 current_user 기반 필터 없음.
4. **빈 칸반 empty-state 메시지 비친절** — `kanban/index.html.erb:269` 단순 빈 div. 액션 유도 없음.
5. **폼 제출 로딩 상태 없음** — 중복 제출 방어 미구현.
6. **에러 메시지 언어 혼재** — `application_controller.rb:31` "Access denied." vs 한국어 혼용.
7. **취소 버튼 없음** — 폼 진입 후 취소 경로 불명확.
8. **설정 최초 진입 가이드 없음** — 신규 사용자가 필수 설정(Gmail 연동, API 키) 인지 불가.

---

## Minor Issues

9. **설정 폼 border-gray-200** — `settings/base/index.html.erb:120` SLDS 최소값 `border-gray-300` 미준수.
10. **이모지 사용** — `settings/base/index.html.erb:146-149` brand-dna anti_pattern 위반.

---

## Recommendations

### 즉시 (P0)
- **신규 사용자 온보딩 플로우** 추가: 첫 로그인 감지 → `/onboarding` 또는 모달로 3단계 체크리스트(1. Gmail 연동 2. 첫 발주 생성 3. 담당자 배정) 안내.

### 단기 (P1)
- **대시보드 읽기전용 배너**: viewer 로그인 시 `dashboard/index.html.erb` 상단에 `kanban/index.html.erb:7-13`과 동일한 읽기전용 안내 추가.
- **내 담당 필터**: `dashboard_controller.rb`에 `@my_orders = orders.joins(:assignments).where(assignments: { user_id: current_user.id }).urgent` 추가.
- **빈 칸반 empty-state**: 각 컬럼 empty-state에 "아직 카드가 없습니다. 신규 발주 버튼으로 시작하세요." + 신규 발주 링크 삽입.
- **폼 로딩 상태**: 제출 버튼에 `data-disable-with="저장 중..."` 추가.
- **Access denied 한국어화**: `application_controller.rb:31` → `"접근 권한이 없습니다."`

### 장기 (P2/P3)
- 역할별 after_sign_in_path_for 오버라이드(admin → `/admin/...`, viewer → `/kanban`)
- 이모지 → Feather SVG 아이콘 교체(설정 알림 스케줄 섹션)
- 주문 폼 취소 버튼 추가
