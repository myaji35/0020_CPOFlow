# @멘션 [읽음] 고도화 — 칸반 카드 미니 타임라인 도트

- **작성일**: 2026-05-09
- **작성자**: CPOFlow PLAN harness (브레인스토밍 결과)
- **상태**: Draft (대표님 검토 대기)
- **연관 영역**: `Notification`, `Comment`, `Task`, `MentionParserService`, 칸반 카드 partial
- **선행 컨텍스트**: 2026-05-09 브레인스토밍 세션 — 농도 4 (미니 타임라인 도트) 채택, 5가지 핵심 결정 권장안 확정

---

## 1. 목적

CPOFlow의 `@멘션` 기능을 단순 알림에서 **책임 추적 + 협업 가시성 + 행동 유도** 3축이 결합된 발주 책임 추적 시스템으로 고도화한다. 칸반 카드 자체에 멘션 응답 결과를 미니 타임라인으로 시각화하여, 발주 단위(=카드 단위) 책임 분포를 0.5초 안에 인지할 수 있도록 한다.

---

## 2. 비목표 (Non-Goals)

- 카톡/Slack 식 "1이 사라졌다" 가벼운 읽음 표시 — 의도적으로 더 무거운 모델 채택
- 멘션 외 일반 알림(visa, contract, due_date 등)에는 도트 시스템 적용하지 않음
- 다국어/i18n 동시 도입 — 한국어 UI 우선 (Production 영어화는 후속 작업)
- 모바일 전용 UX 별도 설계 — 데스크톱 칸반 우선, 모바일은 동일 컴포넌트 자동 축소

---

## 3. 사용자 시나리오

### 시나리오 A — 발신자 (멘션을 보낸 사람)

홍과장이 PO-2026-0481 카드의 코멘트에서 김대리, 이주임, 박과장, 최주임, 정대리 5명을 `@@`(확인 필요)로 멘션. 다음 날 칸반 보드에 들어왔을 때:

- 카드 하단 도트 줄: `○ ○ ◐ ● ●  2/5 확인`
- 좌측부터 미확인 2명, 봤지만 미확인 1명, 확인 완료 2명
- 도트 줄 호버 → "5명 중 2명 확인 / 평균 응답시간 22분 / 미확인: 김대리, 이주임 / [리마인드 보내기]"
- 미확인자 아바타 호버 → 개인 타임라인 (멘션받음 → 카드 펼침 → 확인) 시각

### 시나리오 B — 수신자 (멘션 받은 사람)

김대리가 칸반에 들어왔을 때:

- 본인이 미확인인 카드의 도트 줄에서 본인 도트만 **펄스 애니메이션** (◐ 깜빡)
- 카드 클릭 → 드로어 열림 + 멘션 패널 자동 스크롤 + 본인 멘션 하이라이트
- `[✓ 확인]` 버튼 명시 클릭 → `acknowledged_at` 기록 + Turbo Stream으로 발신자 카드 도트 즉시 변경

### 시나리오 C — 제3자 / 관리자

매니저가 보드 전체를 스캔할 때:

- 빨간 테두리 도트(`○`)가 있는 카드만 시각적으로 튐 — SLA 초과 미확인
- 칸반 칼럼 헤더에 "🔴 3 미확인 멘션" 표시 (해당 칼럼 합계)
- 관리자 모드(admin)에서는 도트 옆에 평균 응답시간 ms 표시 (감사 모드)

---

## 4. 핵심 결정 (5가지) — 권장안 확정

### 결정 1 — 도트 단위: **사람 단위 (B안)**

도트 1개 = 멘션 받은 사람 1명. 같은 사람이 같은 카드에서 여러 번 멘션받아도 1도트로 합산되며, 상태는 **가장 미해결인 상태로 집약**된다 (worst-state aggregation).

- 책임 추적의 본질에 부합 ("누가 미확인인가")
- 칸반 카드 한정 공간에서 의미 밀도 최대화

### 결정 2 — 최대 개수: **5개 + `+N` 오버플로우**

- 도트 5개까지 표시, 초과분은 `+N`
- 호버: "총 7명 — 5명 확인, 2명 미확인 (전체 보기)"
- 클릭: 카드 드로어 열리며 전체 명단 표시

### 결정 3 — 색상: **인텐트 + 상태 이중 인코딩 (5색)**

| 표기 | 의미 | 색 토큰 |
|---|---|---|
| `●` 진녹색 | `@@@` 응답 필요 → 응답 완료 | `colors.success` 짙은 |
| `●` 녹색 | `@@` 확인 필요 → 확인 완료 | `colors.success` |
| `●` 연녹색 | `@` FYI → 자동 read 처리 | `colors.success` 옅은 |
| `◐` 노랑 | 봤지만(viewed) 확인 클릭 안 함 | `colors.warning` |
| `○` 연회색 | 아직 안 봄 | `colors.surface_alt` |
| `○` 빨강 테두리 | SLA 초과 미확인 | `colors.danger` |

시각 우선순위: **빨강 테두리 > 노랑 ◐ > 빈 ○ > 채운 ●** (시선이 미해결로 빨려가도록)

### 결정 4 — 정렬: **미확인 우선 (B안)**

`○ → ◐ → ●` 순으로 왼쪽부터 배치. 카드 한눈 시 좌상단이 가장 먼저 인식되는 영역이므로, 미해결을 거기 모아 "이 카드 문제 있다"가 0.3초 내 인지되도록.

### 결정 5 — 인터랙션

- **개별 도트 호버**: 개인 타임라인 카드 (이름, 멘션받은 시각, 카드 펼친 시각, 확인 시각, 응답 텍스트)
- **도트 줄 호버**: 집계 카드 (확인 비율, 평균 응답시간, 미확인자 명단, [리마인드 보내기] 버튼)
- **클릭**: 카드 드로어 열림 + 멘션 패널로 자동 스크롤 + 미확인자 필터된 상태로 진입

---

## 5. 시각 디테일

### 카드 레이아웃 (멘션 있는 카드만)

```
┌─────────────────────────────┐
│ PO-2026-0481                │  기존 영역
│ Acme Corp · ₩12,400,000     │
│ 👤 홍길동  📅 5/14          │
│ @ ●●●○○  3/5 확인          │  ← 추가 (멘션 0건이면 미렌더)
└─────────────────────────────┘
```

- 카드 높이 +20px (멘션 있을 때만)
- 평균 칸반 밀도 손해 5% 미만 (대부분 카드는 멘션 없음)

### 도트 사이즈 / 상호작용 사이즈

- 기본 도트: **6px**
- 호버 시: 8px로 확대 (transform scale 1.33)
- 클릭 영역(터치 타겟): 도트 주변 24×24px (모바일 접근성)

### 폰트 / 마이크로 카피

- `@` 접두사 텍스트: **mono 폰트** (`design_tokens.typography.font_mono`) — 코드처럼 보여 책임감 시각 코드화
- "3/5 확인" 비율: 본문 폰트, `text-secondary` 색상
- 펄스 애니메이션: `@keyframes pulse` 1.5초 주기, 본인 미확인 도트만

### 발신자/수신자/제3자/관리자 시점 차이

| 보는 사람 | 도트 줄 표현 |
|---|---|
| **발신자** (내가 멘션함) | "내가 5명 멘션 / 3명 확인" + 호버 시 [전체 리마인드] 버튼 |
| **수신자** (내가 멘션받음) | 본인 도트만 펄스 애니메이션 (◐ 깜빡) |
| **제3자** (보드 보는 사람) | 일반 도트만 표시, 인터랙션 호버까지만 |
| **관리자** (admin) | 도트 + 평균 응답시간 ms 표시 (감사 모드) |

---

## 6. 칸반 단계별 의미 차등

발주 단계(`Order.kanban_status`)마다 도트가 의미하는 책임 무게가 다르므로 강조도를 차등 적용:

| 단계 | 도트 강조 |
|---|---|
| `new_rfq`, `make_quo` | 도트 표시 (중간 강조) |
| `pending_po`, `new_po` | 도트 + 미확인자 아바타 1명 노출 (책임자 가시성 ↑) |
| `delivery_items`, `problem` | 빨간 테두리 SLA 강조 (납기 영향) |
| `get_grn`, `done` | 회색 도트만 (감사 기록 모드) |
| `give_up` | 도트 비활성 (의미 없음) |

---

## 7. 데이터 모델

### 7.1 `notifications` 테이블 — 컬럼 추가

```ruby
add_column :notifications, :acknowledged_at,     :datetime
add_column :notifications, :viewed_at,           :datetime
add_column :notifications, :viewed_duration_sec, :integer
add_column :notifications, :intent_level,        :integer, default: 0, null: false
add_column :notifications, :sla_due_at,          :datetime

add_index :notifications, [:notifiable_type, :notifiable_id, :notification_type]
add_index :notifications, :acknowledged_at
add_index :notifications, :sla_due_at
```

| 컬럼 | 의미 |
|---|---|
| `acknowledged_at` | 명시적 [✓ 확인] 클릭 시각 |
| `viewed_at` | 카드 펼침/뷰포트 노출 시작 시각 (자동) |
| `viewed_duration_sec` | 뷰포트 노출 지속 시간 (안티 게이밍 지표) |
| `intent_level` | 0: FYI(`@`), 1: 확인 필요(`@@`), 2: 응답 필요(`@@@`) |
| `sla_due_at` | `@@`/`@@@` 멘션의 응답 마감 시각 (인텐트별 자동 산출) |

기존 `read_at`은 유지 — "드롭다운/페이지에서 알림을 본 시점"의 의미로 분리.

### 7.2 `Order` 멘션 요약 메서드

칸반 N+1 방지를 위해 **카운터 캐시 컬럼** + **단일 집계 메서드** 도입:

```ruby
# orders 테이블 카운터 캐시
add_column :orders, :mention_total_count,        :integer, default: 0, null: false
add_column :orders, :mention_unread_count,       :integer, default: 0, null: false
add_column :orders, :mention_viewed_only_count,  :integer, default: 0, null: false
add_column :orders, :mention_acknowledged_count, :integer, default: 0, null: false
add_column :orders, :mention_sla_overdue_count,  :integer, default: 0, null: false
add_column :orders, :mention_worst_state,        :string  # "unread"|"viewed_only"|"acknowledged"|"sla_overdue"|nil
```

```ruby
class Order < ApplicationRecord
  # 사람 단위 집계 (worst-state aggregation) — 캐시 컬럼 갱신용 메서드
  def recompute_mention_summary!
    rows = Notification.where(notifiable: self, notification_type: "mentioned")
                       .group(:user_id)
                       .pluck(
                         :user_id,
                         Arel.sql("MAX(CASE WHEN acknowledged_at IS NOT NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(CASE WHEN viewed_at IS NOT NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(CASE WHEN sla_due_at < CURRENT_TIMESTAMP AND acknowledged_at IS NULL THEN 1 ELSE 0 END)")
                       )

    counts = { ack: 0, viewed_only: 0, unread: 0, sla_overdue: 0 }
    rows.each do |_uid, ack, viewed, overdue|
      if overdue == 1 then counts[:sla_overdue] += 1
      elsif ack == 1   then counts[:ack] += 1
      elsif viewed == 1 then counts[:viewed_only] += 1
      else counts[:unread] += 1
      end
    end

    worst = if counts[:sla_overdue] > 0  then "sla_overdue"
            elsif counts[:unread] > 0     then "unread"
            elsif counts[:viewed_only] > 0 then "viewed_only"
            elsif counts[:ack] > 0        then "acknowledged"
            else nil
            end

    update_columns(
      mention_total_count:        rows.size,
      mention_unread_count:       counts[:unread],
      mention_viewed_only_count:  counts[:viewed_only],
      mention_acknowledged_count: counts[:ack],
      mention_sla_overdue_count:  counts[:sla_overdue],
      mention_worst_state:        worst,
      updated_at:                 Time.current
    )
  end
end
```

### 7.3 SLA 자동 산출 (Notification 생성 시)

```ruby
class Notification < ApplicationRecord
  before_validation :assign_sla_due_at, on: :create

  def assign_sla_due_at
    return unless notification_type == "mentioned"
    return if sla_due_at.present?

    self.sla_due_at = case intent_level
                      when 1 then 4.hours.from_now   # @@
                      when 2 then 1.hour.from_now    # @@@
                      else nil                       # @ FYI는 SLA 없음
                      end
  end
end
```

조직별 SLA 시간은 후속에서 `Setting`/`Team`에 옮길 수 있는 형태로 시작.

---

## 8. 멘션 인텐트 파싱 강화

`MentionParserService`에 인텐트 레벨 파싱 추가:

```ruby
# @홍길동      → intent_level: 0 (FYI)
# @@홍길동     → intent_level: 1 (확인 필요)
# @@@홍길동    → intent_level: 2 (응답 필요)
MENTION_PATTERN_V2 = /(@{1,3})([A-Z][a-zA-Z]+(?:[ \t][A-Z][a-zA-Z]+)?|[\w가-힣]+)/.freeze
```

매칭 시 `@` 개수를 `intent_level = ats.length - 1`로 환산. 기존 `@홍길동` 호환 유지.

---

## 9. 컴포넌트 / 파셜 구조

```
app/views/orders/
  _kanban_card.html.erb               (기존)
  _mention_dot_strip.html.erb         (신규 — 도트 줄 한 줄)
  _mention_dot.html.erb               (신규 — 단일 도트)

app/views/notifications/
  _mention_acknowledge_button.html.erb (신규 — [✓ 확인] 버튼)
  _mention_timeline_tooltip.html.erb   (신규 — 도트 호버 카드)

app/javascript/controllers/
  mention_dots_controller.js          (신규 — 호버 툴팁, 펄스 애니, 클릭 라우팅)
  mention_viewport_controller.js      (신규 — Intersection Observer로 viewed_at 기록)
```

### `_mention_dot_strip.html.erb` 인터페이스

```erb
<%= render "orders/mention_dot_strip",
           order: order,
           viewer: current_user,
           variant: :kanban_card %>
```

| 파라미터 | 의미 |
|---|---|
| `order` | 대상 발주 |
| `viewer` | 보는 사람 (시점 차등 렌더용) |
| `variant` | `:kanban_card` / `:drawer` / `:column_header` 별 미세 조정 |

---

## 10. Turbo Stream 갱신 흐름

```
사용자 [✓ 확인] 클릭
  → POST /notifications/:id/acknowledge
  → Notification#acknowledge! (acknowledged_at 기록)
  → Order#recompute_mention_summary!
  → Turbo::StreamsChannel.broadcast_render_later_to(
       "order_#{order.id}",
       partial: "orders/mention_dot_strip",
       locals: { order: order, ... })
  → 보드 보고 있는 모든 사용자의 카드 도트가 즉시 갱신
```

뷰포트 노출 시 `viewed_at` 기록도 동일 흐름이지만, **viewed 변경은 별도 캐시 갱신 큐**(SolidQueue) 경유로 부하 분산.

---

## 11. 칼럼 헤더 합계 (Bonus, Phase 2)

```
┌─ make_quo (12) ─────────┐
│  🔴 3 미확인 멘션         │
└─────────────────────────┘
```

`Order.where(kanban_status: ...).sum(:mention_unread_count + mention_sla_overdue_count)` 형태의 단순 합계. 카운터 캐시 컬럼 덕에 N+1 없이 1쿼리.

---

## 12. 칸반 필터 추가

```
[ ] 미확인 멘션 있음     (mention_unread_count > 0 OR mention_viewed_only_count > 0)
[ ] 내가 응답해야 할 멘션 (current_user 본인이 미확인인 카드)
[ ] SLA 초과            (mention_sla_overdue_count > 0)
[ ] 모두 확인 완료       (mention_total_count > 0 AND worst_state = "acknowledged")
```

---

## 13. 안티 게이밍 보호

[✓ 확인] 클릭 시 `viewed_duration_sec` 검사:
- 2초 미만 → 별도 플래그(`fast_acknowledge: true`) — 감사 로그용
- 발신자가 "정말 봤는지 의심" 호버 메뉴에서 재확인 요청 가능 (Phase 2)

자동 `viewed_at` 기록은 **5초 이상 뷰포트 노출** 시에만 (모바일 빠른 스크롤 방지).

---

## 14. 권한 / 프라이버시

- 도트 줄은 **해당 발주에 대한 권한이 있는 사용자**에게만 표시 (기존 Pundit 정책 따름)
- 개인 타임라인 호버 카드는 **발신자 또는 매니저/관리자**에게만 노출
- 일반 viewer 역할은 도트 색상만 보고 호버 상세는 비활성

---

## 15. 성능 / 부하 고려

| 영역 | 대응 |
|---|---|
| 칸반 N개 카드 도트 렌더 | 카운터 캐시 컬럼 5개로 N+1 제거 |
| 다수 사용자 동시 [확인] | `recompute_mention_summary!`를 `update_counters` 기반 원자 갱신으로 |
| Turbo Stream 폭주 | `broadcast_render_later_to` (큐 경유) 사용 |
| `viewed_at` 자동 기록 | Intersection Observer 5초 이상 + debounce |
| SLA 마감 체크 | 시간당 1회 `MentionSlaChecker` Job — 초과 카드만 worst_state 갱신 |

---

## 16. 마이그레이션 / 백필

1. 컬럼 추가 마이그레이션 (notifications + orders)
2. 기존 멘션 알림 백필 rake task:
   - `Notification.where(notification_type: "mentioned")` 전체 순회
   - `read_at`이 있으면 `viewed_at = read_at`으로 복사 (보수적 가정)
   - `acknowledged_at`은 NULL 유지 (소급 확인 처리하지 않음)
   - 모든 영향 받는 `Order#recompute_mention_summary!` 1회 호출
3. 인텐트 파싱은 신규 멘션부터 적용 (기존 `mentioned` 알림은 `intent_level: 0`)

---

## 17. 단계적 도입 (Phase Plan)

| Phase | 범위 | 산출물 |
|---|---|---|
| **Phase 1 (1~2주)** | 컬럼 추가 + 도트 줄 + [✓ 확인] 버튼 + 단순 자동 viewed | 칸반 카드에 도트 표시, 명시 확인 동작 |
| **Phase 2 (1주)** | 인텐트 파싱(`@@`/`@@@`) + SLA 마감 + 빨간 테두리 강조 | 책임 강도 차등 |
| **Phase 3 (1주)** | 호버 타임라인 + 펄스 애니 + Turbo Stream 실시간 갱신 | 협업 가시성 |
| **Phase 4 (1주)** | 칼럼 헤더 합계 + 칸반 필터 + 멘션 대시보드(`/admin/mentions`) | 감사/관리 |
| **Phase 5 (선택)** | 빠른 응답 위젯(👍/⏳/⛔) + 안티 게이밍 강화 | UX 폴리싱 |

---

## 18. 성공 기준 (Karpathy #4 Goal-Driven)

| 지표 | 기준값 |
|---|---|
| **명시 확인율** | 멘션의 60% 이상이 24시간 내 `acknowledged_at` 기록 |
| **평균 응답시간** | `@@` 멘션 평균 4시간 이내 (= SLA 준수율 80%+) |
| **칸반 인지 속도** | 사용자 인터뷰 — "이 카드에 미확인 멘션 있다"를 1초 내 인지 80%+ |
| **카드 밀도** | 도트 줄 추가로 인한 평균 칸반 가시 카드 수 감소 ≤5% |
| **회귀** | 기존 알림 종 드롭다운/멘션 알림 페이지 회귀 0건 |

---

## 19. 리스크 & 완화

| 리스크 | 완화책 |
|---|---|
| 카드 밀도 손해 | 멘션 0건 카드는 도트 줄 미렌더 |
| 빨간 테두리 남용 → 시각 피로 | `@@@` 또는 SLA 초과만 적용, `@@`는 노란 ◐로 |
| `viewed_at` 자동 기록 부정확 | 5초 이상 노출 + Intersection Observer 임계값 조정 |
| 도트 색상 색맹 접근성 | 도트 모양(◐/●/○) + 텍스트 비율(3/5)로 이중 인코딩 |
| 백필 시 부하 | rake task에서 `find_each` + 배치 1000건 단위 |

---

## 20. 결정 요약 (한눈에)

| # | 항목 | 결정 |
|---|---|---|
| 1 | 도트 단위 | **사람 단위** (worst-state aggregation) |
| 2 | 최대 개수 | **5개 + `+N`** |
| 3 | 색상 | **인텐트 + 상태 이중 인코딩 (5색)** |
| 4 | 정렬 | **미확인 우선** (왼쪽) |
| 5 | 인터랙션 | **호버 = 개인 타임라인 / 클릭 = 드로어** |

---

## 21. 후속 작업 트리거

- 본 spec 승인 → `writing-plans` skill로 정식 구현 계획(`docs/superpowers/plans/2026-05-09-mention-kanban-timeline-dots-plan.md`) 작성
- 권한 정책 세부는 구현 계획 단계에서 Pundit 정책 파일 검토와 함께 확정
- 모바일 반응형 미세 조정은 Phase 1 구현 후 디바이스 테스트 결과로 결정
