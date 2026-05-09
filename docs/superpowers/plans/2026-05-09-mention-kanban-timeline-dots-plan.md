# @멘션 칸반 타임라인 도트 — Phase 1 구현 계획

- **작성일**: 2026-05-09
- **이슈**: ISS-353 (P0, IN_PROGRESS)
- **선행 spec**: `docs/superpowers/specs/2026-05-09-mention-kanban-timeline-dots-design.md`
- **범위**: spec §17 Phase 1 — 컬럼 + 도트 줄 + [✓ 확인] + 자동 viewed_at
- **Phase 2~4 비범위**: intent 파싱(`@@`/`@@@`), SLA 마감, 호버 타임라인, 칼럼 헤더 합계, /admin/mentions

---

## 0. 결정 잠금 (Decision Lock)

| 항목 | 결정 | 근거 |
|---|---|---|
| 도트 단위 | 사람 단위 worst-state | spec §4 결정 1 |
| 최대 개수 | 5 + `+N` | spec §4 결정 2 |
| 색상 | 인텐트×상태 5색 (Phase 1은 intent_level=0만 운용 → 사실상 3색 + danger 테두리) | spec §4 결정 3 |
| 정렬 | 미확인 우선 (○ → ◐ → ●) | spec §4 결정 4 |
| 인터랙션 (Phase 1) | 클릭 = 드로어 / 호버 = 단순 title 툴팁 (개인 타임라인 카드는 Phase 3) | spec §17 |
| Turbo 채널명 | `order_#{id}_mentions` (사용자 요구) | 본 계획 §7 |
| viewed_at 임계값 | 5초 연속 노출 | spec §13 |
| 기존 `orders.viewed_at` 컬럼 | **건드리지 않음** — Phase 1은 `notifications.viewed_at`만 추가 | schema.rb 확인 (orders.viewed_at은 별도 의미로 이미 존재) |
| **viewer-self 마킹 방식** (B1) | 서버는 stateless 렌더, 클라이언트가 `<body data-current-user-id>` 읽어 `data-viewer-self` 적용 | eng-review B1-b 채택 (2026-05-09) |
| **i18n 적용 시점** (B2) | Phase 1부터 ko/en yml 동시 등록 — `mentions.dot_strip.*` 키 | eng-review B2-a 채택 (2026-05-09) |
| **after_commit destroy 처리** (B3) | `return if destroyed_by_association.present?` + `after_commit on: %i[create update]` | eng-review B3 채택 (2026-05-09) |

---

## 1. Task Breakdown

원자적·30~120분·1커밋 단위. 의존성 그래프는 §11에 정리.

### T1 — DB 스키마 마이그레이션
- **파일**: `db/migrate/<TS>_add_mention_columns_to_notifications.rb`, `db/migrate/<TS+1>_add_mention_summary_to_orders.rb`
- **내용**:
  - `notifications` +5 컬럼: `acknowledged_at`, `viewed_at`, `viewed_duration_sec`, `intent_level`, `sla_due_at`
  - `orders` +6 컬럼: `mention_total_count`, `mention_unread_count`, `mention_viewed_only_count`, `mention_acknowledged_count`, `mention_sla_overdue_count`, `mention_worst_state` (spec는 +5라 적었으나 worst_state까지 포함하면 6 — 본 계획에서 정정)
  - 인덱스 3종 (§2 참조)
- **수용 기준**: `bin/rails db:migrate` 통과 → `bin/rails db:rollback` 통과 → 다시 migrate 통과 (양방향성). schema.rb diff 깔끔.
- **예상 커밋**: 1

### T2 — Notification 모델 강화
- **파일**: `app/models/notification.rb`
- **내용**:
  - `MENTIONED_TYPE = "mentioned"` 상수
  - 스코프 추가: `mentions`, `unacknowledged`
  - 메서드 추가: `acknowledged?`, `viewed?`, `acknowledge!(viewer:)`, `mark_viewed!(duration_sec:)`
  - `assign_default_intent_level` before_validation (Phase 1은 항상 0 — Phase 2에서 파싱 강화) — 단순히 `self.intent_level ||= 0`
  - **after_commit 훅** — `notifiable`이 Order이고 `notification_type == "mentioned"`일 때 `notifiable.recompute_mention_summary!` 호출 + Turbo broadcast
  - 기존 `read?`, `read!`, `category` 동작 회귀 0건 보장
- **수용 기준**: `test/models/notification_test.rb` 기존 6개 테스트 통과 + 신규 8개 추가 테스트(아래 §8) 통과
- **예상 커밋**: 1

### T3 — Order#recompute_mention_summary!
- **파일**: `app/models/order.rb` (말미에 신규 메서드 군)
- **내용**:
  - `recompute_mention_summary!` — spec §7.2 SQL 그대로 (단일 GROUP BY 쿼리, `update_columns`로 콜백 회피)
  - `mention_summary_dots(viewer:, limit: 5)` — 도트 줄 렌더용 hash 배열 반환 (사람×worst-state 정렬된 형태)
  - 기존 Order 콜백/검증 회귀 0
- **수용 기준**: 신규 모델 테스트 (5개 멘션 → 정확한 카운트 5종), `update_columns`라 `updated_at` 충돌 없음, lock_version 증가시키지 않음 (carrier 콜백 회피 검증)
- **예상 커밋**: 1

### T4 — 라우트 + 컨트롤러 (acknowledge, view)
- **파일**: `config/routes.rb`, `app/controllers/notifications_controller.rb`
- **내용**:
  - 라우트:
    ```ruby
    resources :notifications, only: %i[index] do
      collection { patch :read_all }
      member do
        patch :read
        patch :acknowledge   # 신규
        patch :view          # 신규 (단건 viewport tick — 5초 도달 시 호출)
      end
    end
    ```
  - `#acknowledge` — `current_user.notifications.find` → `notification.acknowledge!(viewer: current_user)` → respond_to turbo_stream/json
  - `#view` — `notification.mark_viewed!(duration_sec: params[:duration].to_i)`
  - 권한: `current_user.notifications.find` 자체가 본인 소유로 스코프 — Pundit 추가 정책 불필요 (기존 `#read`와 동일 패턴)
  - **viewport 단건 endpoint 채택 사유**: 칸반 카드 한 개에 멘션 0~7건 — 배치 보낼 만한 양이 아님. Phase 1에선 단순 PATCH 단건이 카르파시 단순성 원칙에 부합. 부하 측정 결과 문제 시 Phase 3에서 batch endpoint로 승격.
- **수용 기준**: `bin/rails routes | grep notifications` → 5개 (index, read_all, read, acknowledge, view), 컨트롤러 unit test 3개 통과
- **예상 커밋**: 1

### T5 — Turbo Broadcast 채널 통합
- **파일**: `app/models/notification.rb` (after_commit), `app/views/orders/_mention_dot_strip.html.erb` (turbo_frame 래핑), `app/views/kanban/_card.html.erb` (turbo_stream_from 추가)
- **내용**:
  - 채널명: `"order_#{order.id}_mentions"` (요구사항 그대로)
  - target: `"mention-dot-strip-#{order.id}"`
  - broadcast 시점: Notification#after_commit (acknowledge / view / create 시) → `Order#recompute_mention_summary!` → `Turbo::StreamsChannel.broadcast_replace_to`
  - 칸반 카드 렌더 시 `<%= turbo_stream_from "order_#{order.id}_mentions" if order.mention_total_count > 0 %>`
  - 멘션 0건 카드는 Cable 구독도 안 함 (부하 절감)
- **수용 기준**: 사용자 A가 [✓ 확인] 클릭 → 사용자 B의 칸반에서 도트가 즉시(<2s) 갱신. 멘션 0건 카드는 `turbo-cable-stream-source` 미렌더.
- **예상 커밋**: 1

### T6 — `_mention_dot_strip` 파셜 + i18n 키
- **파일**:
  - `app/views/orders/_mention_dot_strip.html.erb` (신규)
  - `config/locales/ko.yml` (키 추가)
  - `config/locales/en.yml` (키 추가)
- **내용**: spec §9 인터페이스 + i18n
  ```erb
  <%# locals: order, viewer, variant: %>
  <% return if order.mention_total_count.to_i == 0 %>
  <% dots = order.mention_summary_dots(viewer: viewer, limit: 5) %>
  <% overflow = order.mention_total_count - dots.size %>
  <div id="mention-dot-strip-<%= order.id %>"
       class="mention-dot-strip flex items-center gap-1 mt-1.5 pt-1.5 border-t border-ink-100"
       data-controller="mention-dots mention-viewport"
       data-mention-viewport-order-id-value="<%= order.id %>"
       data-mention-viewport-threshold-value="5000">
    <span class="font-mono text-[10px] text-ink-500"><%= t("mentions.dot_strip.symbol") %></span>
    <% dots.each do |dot| %>
      <%= render "orders/mention_dot", dot: dot %>
    <% end %>
    <% if overflow > 0 %>
      <span class="text-[10px] text-ink-500"><%= t("mentions.dot_strip.overflow_count", count: overflow) %></span>
    <% end %>
    <span class="text-[10px] text-ink-500 ml-1">
      <%= t("mentions.dot_strip.acknowledged_count",
             ack: order.mention_acknowledged_count,
             total: order.mention_total_count) %>
    </span>
  </div>
  ```
  - i18n 키:
    ```yaml
    # config/locales/ko.yml
    ko:
      mentions:
        dot_strip:
          symbol: "@"
          overflow_count: "+%{count}"
          acknowledged_count: "%{ack}/%{total} 확인"
    # config/locales/en.yml
    en:
      mentions:
        dot_strip:
          symbol: "@"
          overflow_count: "+%{count}"
          acknowledged_count: "%{ack}/%{total} ack"
    ```
- **B1-b 변경**: partial은 `viewer` local을 받지 않음. `dot` hash에서 `is_viewer_self`를 제거하고 클라이언트가 마킹.
- **수용 기준**: 5개 멘션 + 2 unread + 3 acknowledged → DOM에 `○○●●●` 순서대로 렌더. 멘션 0건 → 컨테이너 자체 미출력. ko 환경 "확인" / en 환경 "ack" 표기.
- **예상 커밋**: 1

### T7 — `_mention_dot` 파셜
- **파일**: `app/views/orders/_mention_dot.html.erb` (신규)
- **내용**:
  - locals: `dot` (hash: `{user_id, user_name, state, notification_id, intent_level}`) — **viewer 제거(B1-b)**
  - 도트 wrapper에 `data-user-id="<%= dot[:user_id] %>"` 출력 → 클라이언트가 본인 여부 판정
  - 상태별 클래스 매핑 (Phase 1은 4가지: `unread`, `viewed_only`, `acknowledged`, `sla_overdue`)
    - `unread` → `bg-ink-200 border border-ink-300` (회색 ○ 느낌)
    - `viewed_only` → `bg-amber-400` (노랑 ◐) — half-fill은 conic-gradient로
    - `acknowledged` → `bg-emerald-500` (녹색 ●)
    - `sla_overdue` → `bg-white border-2 border-red-500` (Phase 1 미사용이지만 클래스만 준비)
  - 사이즈: 6px (w-1.5 h-1.5), 호버 시 8px (hover:scale-[1.33] transition-transform)
  - 클릭 영역: 24x24px wrapper (touch target) — 카드 클릭 이벤트 충돌 막기 위해 `data-prevent-card-open` 속성 + `event.stopPropagation()`
  - tooltip: `title="#{dot[:user_name]} — #{state_label}"` (Phase 1은 native title만, 호버 카드는 Phase 3)
- **수용 기준**: 4가지 state가 각각 다른 색상으로 렌더, 호버 시 사이즈 확대, 모바일 터치 영역 24px 보장
- **예상 커밋**: 1

### T8 — 칸반 카드 통합
- **파일**: `app/views/kanban/_card.html.erb`
- **내용**: `<!-- Footer: Assignees + Meta -->` 직전에 1줄 삽입:
  ```erb
  <%= render "orders/mention_dot_strip", order: order, viewer: current_user, variant: :kanban_card %>
  ```
- **카드 높이 영향**: 멘션 0건 → +0px (return), 멘션 ≥1건 → +20px. spec §5 카드 레이아웃 그대로.
- **수용 기준**: 멘션 0건 카드 평균 높이 변화 없음 (회귀), 멘션 있는 카드만 도트 줄 노출
- **예상 커밋**: 1

### T9 — Stimulus: `mention_dots_controller.js`
- **파일**: `app/javascript/controllers/mention_dots_controller.js` (신규)
- **내용** (Phase 1 최소): 50줄 미만
  - `static targets = ["dot"]`
  - `acknowledge(event)` action — 단일 도트 클릭 시 fetch PATCH `/notifications/:id/acknowledge` + Turbo Stream 응답 자동 적용
  - `event.stopPropagation()`로 카드 onclick 방지
- **수용 기준**: 도트 클릭 → 카드 드로어 열리지 않음 + acknowledge endpoint 호출
- **예상 커밋**: 1
- **주의**: `[✓ 확인]` 버튼은 Phase 1에서 **드로어 멘션 패널 안의 명시 버튼**으로 구현 (T11). 도트 자체 클릭은 Phase 1에선 카드 드로어 열기로만 동작 (spec §4 결정 5). 단 viewer == 본인이고 본인이 unread 상태면 도트 클릭 자체로 acknowledge 가능 — UX 단축. Phase 3에서 hover card로 분리.

### T10 — Stimulus: `mention_viewport_controller.js`
- **파일**: `app/javascript/controllers/mention_viewport_controller.js` (신규)
- **내용**:
  - IntersectionObserver, threshold 0.5
  - 5초 (5000ms) 연속 노출 시 PATCH `/notifications/:id/view?duration=5`
  - **important**: viewport는 **카드 단위가 아니라 strip 단위** — strip이 보이면 그 strip의 viewer 본인 unread notifications만 view 처리
  - debounce: 같은 카드에서 5초 도달 후 후속 호출은 30초 차단 (data attr 마킹)
  - `disconnect()` clean up observer
- **수용 기준**: 칸반에 멘션 카드 노출 → 5초 후 본인 viewed_at 기록, 빠른 스크롤(<5s) 시 미기록
- **예상 커밋**: 1

### T11 — 드로어 안 멘션 패널 + [✓ 확인] 버튼
- **파일**:
  - `app/views/notifications/_mention_acknowledge_button.html.erb` (신규)
  - `app/views/orders/_drawer_content.html.erb` (코멘트 탭 안에 멘션 섹션 추가)
- **내용**:
  - 드로어 코멘트 탭 상단에 "이 카드의 @멘션" 섹션 — 본인 unread/viewed-only인 멘션만 추리고 [✓ 확인] 버튼 노출
  - 버튼 form: `button_to "✓ 확인", acknowledge_notification_path(n), method: :patch, class: "..."`
  - 클릭 시 acknowledge → Turbo Stream으로 도트 줄 갱신 + 버튼 자체는 "확인됨 (방금)"으로 교체
- **수용 기준**: 시나리오 B (수신자) — 드로어 열고 [✓ 확인] 클릭 → 도트가 ○ → ● 즉시 변경 + 발신자 화면도 동기화
- **예상 커밋**: 1

### T12 — 백필 rake task
- **파일**: `lib/tasks/mention_summary_backfill.rake` (신규)
- **내용**: §9 상세
- **수용 기준**: dry-run 옵션, find_each(batch_size: 1000), 진행률 로그
- **예상 커밋**: 1

### T13 — 모델 테스트
- **파일**: `test/models/notification_test.rb` (확장), `test/models/order_test.rb` (신규 또는 확장)
- **내용**: §8 상세
- **예상 커밋**: 1

### T14 — 컨트롤러 테스트
- **파일**: `test/controllers/notifications_controller_test.rb` (확장)
- **예상 커밋**: 1

### T15 — System test (Capybara) — 페르소나별
- **파일**: `test/system/mention_dots_test.rb` (신규)
- **내용**: §8 페르소나 테스트 4종 (sender / receiver / 3rd-party / admin)
- **예상 커밋**: 1

### T16 — 회귀 방지 + 헤더 드롭다운/알림 페이지 검증
- **파일**: `test/controllers/notifications_controller_test.rb` (read/read_all 회귀 테스트), `test/services/mention_parser_service_test.rb` (멘션 생성 시 `intent_level: 0` 자동 할당 검증)
- **예상 커밋**: 1

### T17 — Post-deploy real-click verification 자동화 스크립트
- **파일**: `script/verify_mention_phase1.rb` 또는 `lib/tasks/verify_mention_phase1.rake` (신규, 본 계획 §10에서 강제)
- **내용**: 3-op 실 클릭 검증 (CPOFlow 룰)
  1. **Create**: 코멘트에 `@홍길동` 작성 → notifications row 생겨야 + 칸반 도트 줄 ○ 1개 노출
  2. **Update**: [✓ 확인] 클릭 → acknowledged_at 채워짐 + 도트 ○ → ●
  3. **Delete**: Order delete → notifications dependent: :destroy 동작
- **방식**: gstack `/browse` skill로 headless 검증 + DB 직접 검사
- **수용 기준**: CI 또는 manual 실행으로 3-op 모두 통과
- **예상 커밋**: 1

**총 작업: 17 / 예상 커밋: 17**

---

## 2. Migration Strategy

### 2.1 컬럼 타입

```ruby
# db/migrate/<TS>_add_mention_columns_to_notifications.rb
class AddMentionColumnsToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :acknowledged_at,     :datetime
    add_column :notifications, :viewed_at,           :datetime
    add_column :notifications, :viewed_duration_sec, :integer
    add_column :notifications, :intent_level,        :integer, default: 0, null: false
    add_column :notifications, :sla_due_at,          :datetime

    add_index :notifications, [:notifiable_type, :notifiable_id, :notification_type],
              name: "idx_notifications_polymorphic_type"
    add_index :notifications, :acknowledged_at
    add_index :notifications, :sla_due_at
  end
end
```

```ruby
# db/migrate/<TS+1>_add_mention_summary_to_orders.rb
class AddMentionSummaryToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :mention_total_count,        :integer, default: 0, null: false
    add_column :orders, :mention_unread_count,       :integer, default: 0, null: false
    add_column :orders, :mention_viewed_only_count,  :integer, default: 0, null: false
    add_column :orders, :mention_acknowledged_count, :integer, default: 0, null: false
    add_column :orders, :mention_sla_overdue_count,  :integer, default: 0, null: false
    add_column :orders, :mention_worst_state,        :string
    add_index :orders, :mention_total_count,
              name: "idx_orders_mention_total",
              where: "mention_total_count > 0"
  end
end
```

### 2.2 SQLite 특이사항

| 이슈 | 대응 |
|---|---|
| **JSON 컬럼 금지** | 모든 컬럼 scalar — OK |
| **advisory lock 없음** | `update_counters` 또는 `update_columns`만 사용 — 트랜잭션 + 행 단위 락만 의존. `recompute_mention_summary!`는 idempotent해서 race time이어도 결과 수렴 (worst-state는 절대 결정적 함수). |
| **partial index 가능** | SQLite 3.8+ 지원, `where:` 옵션 사용 가능 |
| **DEFAULT NOT NULL on existing rows** | 마이그레이션 시 default 값 일괄 채움 → orders는 default: 0 → 기존 행 자동 0 |
| **lock_version 충돌** | `update_columns`는 callbacks/validations/lock_version 모두 우회 — spec §7.2 의도와 일치 |
| **WAL 모드 동시성** | 멀티 작성자 환경에서 read 동시성은 OK. 다중 [✓ 확인] 클릭 race는 §3에서 다룸. |

### 2.3 백필

- **Notification 측**: `read_at`이 있으면 `viewed_at = read_at`으로 복사 (보수 추정 — "본 시점"으로 간주). `acknowledged_at`은 NULL 유지.
- **Order 측**: 영향받는 모든 Order에 `recompute_mention_summary!` 호출.
- 자세한 절차는 §9.

---

## 3. Model Layer

### 3.1 `Notification` 강화

```ruby
class Notification < ApplicationRecord
  MENTIONED_TYPE = "mentioned"
  STATE_UNREAD = "unread"
  STATE_VIEWED_ONLY = "viewed_only"
  STATE_ACKNOWLEDGED = "acknowledged"
  STATE_SLA_OVERDUE = "sla_overdue"

  scope :mentions,         -> { where(notification_type: MENTIONED_TYPE) }
  scope :unacknowledged,   -> { where(acknowledged_at: nil) }
  scope :unviewed,         -> { where(viewed_at: nil) }

  before_validation -> { self.intent_level ||= 0 }

  after_commit :sync_order_mention_summary, on: %i[create update]

  def acknowledged?       = acknowledged_at.present?
  def viewed?             = viewed_at.present?
  def mention?            = notification_type == MENTIONED_TYPE

  def acknowledge!(viewer:)
    return if acknowledged?
    return unless user_id == viewer.id
    update!(acknowledged_at: Time.current, read_at: read_at || Time.current)
  end

  def mark_viewed!(duration_sec:)
    return if viewed?
    update!(
      viewed_at: Time.current,
      viewed_duration_sec: duration_sec
    )
  end

  private

  def sync_order_mention_summary
    return if destroyed_by_association.present?  # B3: Order dependent: :destroy 가드
    return unless notification_type == MENTIONED_TYPE
    return unless notifiable.is_a?(Order)
    notifiable.recompute_mention_summary!
    Turbo::StreamsChannel.broadcast_replace_to(
      "order_#{notifiable.id}_mentions",
      target:  "mention-dot-strip-#{notifiable.id}",
      partial: "orders/mention_dot_strip",
      locals:  { order: notifiable, viewer: nil, variant: :kanban_card }
    )
  rescue StandardError => e
    Rails.logger.warn "[Notification#sync] #{e.class}: #{e.message}"
  end
end
```

**B1-b 결정 (2026-05-09)**: broadcast는 stateless `viewer: nil`로 전송. 클라이언트(Stimulus)가 `<body data-current-user-id>` 읽어 broadcast 후에도 본인 도트에 `data-viewer-self="true"` 자동 마킹. self-acknowledge 단축이 cross-user broadcast 후에도 유지.

**B3 결정 (2026-05-09)**: `destroyed_by_association` 가드 + `on: %i[create update]`로 destroy 케이스 명시 제외. Order 삭제 시 자식 notifications가 같은 트랜잭션에서 destroy되지만 callback은 무발화 — 어차피 Order 자체가 사라져 broadcast target도 없음.

### 3.2 `Order#recompute_mention_summary!`

spec §7.2 SQL 그대로. 단일 GROUP BY 쿼리 + 메모리 분기. **CURRENT_TIMESTAMP**는 SQLite/Postgres 양쪽 모두 표준 → ANSI compatible.

```ruby
class Order < ApplicationRecord
  def recompute_mention_summary!
    rows = Notification.where(notifiable: self, notification_type: "mentioned")
                       .group(:user_id)
                       .pluck(
                         :user_id,
                         Arel.sql("MAX(CASE WHEN acknowledged_at IS NOT NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(CASE WHEN viewed_at IS NOT NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(CASE WHEN sla_due_at IS NOT NULL AND sla_due_at < CURRENT_TIMESTAMP AND acknowledged_at IS NULL THEN 1 ELSE 0 END)")
                       )

    counts = { ack: 0, viewed_only: 0, unread: 0, sla_overdue: 0 }
    rows.each do |_uid, ack, viewed, overdue|
      if overdue == 1     then counts[:sla_overdue] += 1
      elsif ack == 1      then counts[:ack] += 1
      elsif viewed == 1   then counts[:viewed_only] += 1
      else                     counts[:unread] += 1
      end
    end

    worst = if counts[:sla_overdue] > 0     then "sla_overdue"
            elsif counts[:unread] > 0       then "unread"
            elsif counts[:viewed_only] > 0  then "viewed_only"
            elsif counts[:ack] > 0          then "acknowledged"
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

  def mention_summary_dots(viewer:, limit: 5)
    Notification.where(notifiable: self, notification_type: "mentioned")
                .group(:user_id)
                .order(Arel.sql("MIN(acknowledged_at) IS NULL DESC, MIN(viewed_at) IS NULL DESC"))
                .pluck(
                  :user_id,
                  Arel.sql("MAX(CASE WHEN acknowledged_at IS NOT NULL THEN 1 ELSE 0 END) AS ack"),
                  Arel.sql("MAX(CASE WHEN viewed_at IS NOT NULL THEN 1 ELSE 0 END) AS viewed"),
                  Arel.sql("MAX(id) AS latest_notif_id")
                )
                .first(limit)
                .map do |uid, ack, viewed, nid|
                  state = if ack == 1 then "acknowledged"
                          elsif viewed == 1 then "viewed_only"
                          else "unread"
                          end
                  user = User.find_by(id: uid)
                  {
                    user_id: uid,
                    user_name: user&.display_name || "?",
                    state: state,
                    notification_id: nid,
                    is_viewer_self: viewer && uid == viewer.id
                  }
                end
  end
end
```

**Race condition 처리**: 두 사용자가 동시에 [✓ 확인] 클릭 시 — `update!`은 행 단위 락(SQLite WAL), `recompute_mention_summary!`는 idempotent. 마지막 호출이 정확한 카운트로 수렴. **Lost update 위험 0** because each call recomputes from scratch.

### 3.3 `MentionParserService` 호환성 (Phase 1 무수정)

기존 `MentionParserService`가 만드는 `Notification.create!`는 `intent_level`을 명시하지 않음 → `before_validation` 훅이 0으로 채움 → `after_commit`이 `sync_order_mention_summary` 발화 → 신규 멘션 코멘트 작성 즉시 카운터 캐시 자동 갱신.

**`MentionParserService` 자체는 Phase 1에서 한 줄도 수정하지 않음** — Karpathy surgical changes 원칙 준수.

---

## 4. Controller / Routes

### 4.1 라우트

```ruby
resources :notifications, only: %i[index] do
  collection { patch :read_all }
  member do
    patch :read
    patch :acknowledge
    patch :view
  end
end
```

### 4.2 `NotificationsController` 확장

```ruby
def acknowledge
  notification = current_user.notifications.find(params[:id])
  notification.acknowledge!(viewer: current_user)
  respond_to do |format|
    format.turbo_stream { head :ok }
    format.json         { head :ok }
    format.html         { redirect_back fallback_location: notifications_path }
  end
end

def view
  notification = current_user.notifications.find(params[:id])
  duration = params[:duration].to_i.clamp(0, 3600)
  notification.mark_viewed!(duration_sec: duration)
  head :ok
end
```

**보안**: `current_user.notifications.find` → 본인 소유만. 다른 사용자의 notification id 추측해서 `acknowledge` 시도 → `ActiveRecord::RecordNotFound` (404).

### 4.3 단건 vs 배치 endpoint

| 옵션 | 장 | 단 | 결정 |
|---|---|---|---|
| 단건 PATCH | 코드 50줄, REST 표준 | 카드당 멘션 N개면 N개 요청 | **Phase 1 채택** |
| 배치 PATCH `[ids]` | 1요청 N건 | 추가 컨트롤러 + JSON 파싱 + 권한 N검증 | Phase 3 부하 측정 후 |

평균 카드당 멘션 1~3건 → Phase 1 단건으로 충분.

---

## 5. View Partial Tree

```
app/views/orders/
  _mention_dot_strip.html.erb     [신규 — T6]
  _mention_dot.html.erb           [신규 — T7]
  _drawer_content.html.erb        [수정 — T11]

app/views/notifications/
  _mention_acknowledge_button.html.erb  [신규 — T11]

app/views/kanban/
  _card.html.erb                  [수정 — T8, 1줄 삽입]
```

### 5.1 조건부 렌더 게이트

**3중 게이트**:
1. T6 파셜 첫 줄: `<% return if order.mention_total_count.to_i == 0 %>` — DB 조회 0
2. T8 카드 통합: `<%= render "orders/mention_dot_strip", ... %>` 자체는 항상 호출하되 위 return으로 자르기
3. T5 broadcast 구독: `<%= turbo_stream_from "order_#{order.id}_mentions" if order.mention_total_count > 0 %>` — Cable 부하 절감

### 5.2 Locals 인터페이스

| Partial | Required | Optional |
|---|---|---|
| `_mention_dot_strip` | `order`, `viewer` | `variant: :kanban_card` (기본) |
| `_mention_dot` | `dot`, `viewer` | — |
| `_mention_acknowledge_button` | `notification` | — |

`viewer == nil` 케이스 (Turbo broadcast의 generalized partial)도 안전 처리.

---

## 6. Stimulus Controllers

### 6.1 `mention_dots_controller.js` — B1-b 클라이언트 viewer-self 마킹

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dot"]

  connect() {
    this.markViewerSelf()
  }

  // Turbo Stream broadcast 후에도 다시 호출되도록 MutationObserver 사용
  // (broadcast_replace_to가 partial을 통째로 바꾸면 connect()가 재호출됨 — 자동 처리)
  markViewerSelf() {
    const currentUserId = document.body.dataset.currentUserId
    if (!currentUserId) return
    this.element.querySelectorAll('[data-user-id]').forEach((el) => {
      if (el.dataset.userId === currentUserId) {
        el.dataset.viewerSelf = "true"
      }
    })
  }

  acknowledge(event) {
    const dotEl = event.currentTarget
    const notifId = dotEl.dataset.notificationId
    const isSelf  = dotEl.dataset.viewerSelf === "true"
    if (!isSelf || !notifId) return

    event.stopPropagation()
    event.preventDefault()
    fetch(`/notifications/${notifId}/acknowledge`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
  }
}
```

**B1-b 보강 요건**:
- `app/views/layouts/application.html.erb`의 `<body>`에 `data-current-user-id="<%= current_user&.id %>"` 추가
- `_mention_dot.html.erb`의 도트 wrapper에 `data-user-id="<%= dot[:user_id] %>"` 출력 (서버는 본인 여부 판정 안 함)
- Stimulus `connect()`는 Turbo Stream broadcast로 partial이 교체될 때마다 재호출됨 → 자동 마킹 유지

### 6.2 `mention_viewport_controller.js` — Intersection Observer 5초

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    orderId: Number,
    threshold: { type: Number, default: 5000 }
  }

  connect() {
    this.timers = new Map()
    this.fired  = new Set()
    this.observer = new IntersectionObserver(this.onIntersect.bind(this), {
      threshold: 0.5
    })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.timers.forEach((t) => clearTimeout(t))
    this.timers.clear()
  }

  onIntersect(entries) {
    entries.forEach((entry) => {
      const selfDots = this.element.querySelectorAll('[data-viewer-self="true"][data-state="unread"]')
      selfDots.forEach((dot) => {
        const nid = dot.dataset.notificationId
        if (!nid || this.fired.has(nid)) return

        if (entry.isIntersecting) {
          if (!this.timers.has(nid)) {
            const t = setTimeout(() => this.fireView(nid), this.thresholdValue)
            this.timers.set(nid, t)
          }
        } else {
          const t = this.timers.get(nid)
          if (t) { clearTimeout(t); this.timers.delete(nid) }
        }
      })
    })
  }

  fireView(notifId) {
    if (this.fired.has(notifId)) return
    this.fired.add(notifId)
    this.timers.delete(notifId)
    fetch(`/notifications/${notifId}/view?duration=5`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
        "Accept": "application/json"
      }
    })
  }
}
```

**디바운스 전략**: `fired` Set으로 같은 notification 중복 호출 차단. 빠른 스크롤 (5초 미만 노출) 시 setTimeout 취소.

---

## 7. Turbo Stream Wiring

### 7.1 채널 이름

`order_#{order.id}_mentions` — 사용자 명시 요구.

### 7.2 구독자 (turbo_stream_from)

칸반 카드 안 멘션 dot strip 위에서 구독:
```erb
<% if order.mention_total_count > 0 %>
  <%= turbo_stream_from "order_#{order.id}_mentions" %>
<% end %>
<%= render "orders/mention_dot_strip", order: order, viewer: current_user %>
```

드로어 코멘트 탭 안에서도 동일 구독.

### 7.3 발신자 (broadcast_replace_to)

3개 trigger 시점, 모두 `Notification#after_commit`에서 자동:
1. **Create**: 새 멘션 알림 생성
2. **Update**: `acknowledge!` / `mark_viewed!` 호출
3. **Destroy**: notification 삭제

### 7.4 부하 분산

- spec §15 "broadcast_render_later_to (큐 경유)"는 Phase 3에서 검토 — Phase 1은 동기 broadcast로 시작
- 멘션 0건 카드는 turbo_stream_from 미실행 → Cable 구독 자체 X
- broadcast 송신 비용은 Order당 1회. 페이로드는 dot strip partial (~1KB)

---

## 8. Testing Strategy

### 8.1 모델 unit (T13)

**`test/models/notification_test.rb` 추가**:
- mentions scope returns only mentioned type
- unacknowledged scope filters acknowledged_at IS NULL
- intent_level defaults to 0 on create
- acknowledge! sets acknowledged_at + read_at
- acknowledge! is idempotent (no-op on re-call)
- acknowledge! rejects non-owner (viewer != user)
- mark_viewed! sets viewed_at + duration
- after_commit triggers Order#recompute_mention_summary! for mentions only
- after_commit no-op for non-mention notifications (회귀 0건)

**`test/models/order_test.rb` 신규**:
- recompute_mention_summary! with 0 mentions → all counts = 0, worst = nil
- recompute_mention_summary! 5명 mentions all unread → unread_count=5, worst="unread"
- recompute_mention_summary! 동일 user 다중 멘션 → 1 dot으로 집약 (worst-state)
- recompute_mention_summary! 2 ack + 1 viewed_only + 2 unread → worst="unread"
- recompute_mention_summary! does not increment lock_version
- mention_summary_dots returns dots in unread-first order
- mention_summary_dots respects limit (5 + +N 케이스)

### 8.2 컨트롤러 (T14)

- PATCH /notifications/:id/acknowledge → 200 + acknowledged_at set
- PATCH /notifications/:id/acknowledge for non-owner → 404
- PATCH /notifications/:id/acknowledge twice → idempotent
- PATCH /notifications/:id/view?duration=5 → viewed_at set, duration recorded
- PATCH /notifications/:id/view duration=99999 → clamped to 3600
- 회귀: 기존 read / read_all / index 동작 변화 0
- 회귀: notifications#index의 카테고리 필터 (mentioned 카테고리 카운트)

### 8.3 시스템 테스트 (T15) — 페르소나 4종

**`test/system/mention_dots_test.rb` (신규, Capybara)**:

- **시나리오 A: 발신자** — 멘션 5명 후 도트 줄 5개 노출 + 3/5 확인 텍스트
- **시나리오 B: 수신자** — 본인 도트는 viewer-self 마킹 + acknowledge 시 즉시 ●
- **시나리오 C: 제3자** — 도트 보이지만 acknowledge 시도 시 권한 없음 (UI 버튼 미노출, 직접 호출 시 404)
- **시나리오 D: 관리자** — 도트 + 텍스트 비율 노출 (Phase 1은 평균 응답시간 미구현)

### 8.4 회귀 (T16)

- MentionParserService — 기존 @홍길동 → Notification.create! 시 intent_level=0 자동 set
- 헤더 종 드롭다운 — mentions 카테고리 unread count 정확
- /notifications 페이지 — mentioned 필터 동작
- 칸반 인덱스 페이지 — 멘션 0건 카드 높이 변화 없음 (시각 회귀)

---

## 9. Rollout / Backfill

### 9.1 배포 순서

1. **Migrate** (T1) — 신규 컬럼 default 값으로 기존 행 자동 채움
2. **Code deploy** (T2~T11) — 멘션 0건인 카드는 도트 줄 미렌더 → 기존 카드 변화 0
3. **Backfill rake** (T12) — `bin/rails mentions:backfill_phase1` 실행
4. **Verify** (T17) — `bin/rails mentions:verify_phase1` 3-op 검증

### 9.2 백필 rake task spec

```ruby
# lib/tasks/mention_summary_backfill.rake
namespace :mentions do
  desc "Phase 1 백필: notifications.viewed_at = read_at 복사 + 영향 Order recompute"
  task :backfill_phase1, [:dry_run] => :environment do |_, args|
    dry = args[:dry_run] == "true"

    puts "[mention:backfill] dry_run=#{dry} 시작"

    target = Notification.where(notification_type: "mentioned")
                         .where.not(read_at: nil)
                         .where(viewed_at: nil)
    count = target.count
    puts "[1/2] viewed_at 백필 대상: #{count}건"

    unless dry
      target.find_each(batch_size: 1000).with_index do |n, i|
        n.update_columns(viewed_at: n.read_at)
        puts "  진행: #{i+1}/#{count}" if (i+1) % 1000 == 0
      end
    end

    affected_order_ids = Notification.where(notification_type: "mentioned")
                                     .where(notifiable_type: "Order")
                                     .distinct
                                     .pluck(:notifiable_id)
    puts "[2/2] 영향 Order 재계산 대상: #{affected_order_ids.size}건"

    unless dry
      Order.where(id: affected_order_ids).find_each(batch_size: 100).with_index do |o, i|
        o.recompute_mention_summary!
        puts "  진행: #{i+1}/#{affected_order_ids.size}" if (i+1) % 100 == 0
      end
    end

    puts "[mention:backfill] 완료"
  end
end
```

**1단계 콜백 우회 이유**: 1만 건 백필 시 `update!` → `after_commit` → broadcast 1만 회 폭주 방지.

### 9.3 롤백 절차

마이그레이션 down도 reversible — Rails가 자동으로 add_column ↔ remove_column. 단, 데이터 손실 방지를 위해 `bin/rails db:rollback STEP=2` 전 백업 필수.

---

## 10. Risk Register

| # | 리스크 | 영향 | 완화 |
|---|---|---|---|
| R1 | **SQLite 마이그레이션 실패** | 배포 차단 | 1) backup 필수. 2) Rails 8.1은 SQLite default 채움 빠름. 3) `bin/rails db:rollback` 사전 검증. |
| R2 | **칸반 N+1** | 페이지 로드 +1초 | 카운터 캐시 컬럼 6개로 N+1 0. `mention_summary_dots`는 strip이 보일 때만 호출. 100개 카드 중 ~10건 멘션 가정 → +10쿼리. 허용 범위. |
| R3 | **Turbo Stream broadcast 폭주** | Cable 부하 | 1) 멘션 0건 카드 미구독. 2) Phase 1은 동기 broadcast — 기록 보기. 3) 50동시 사용자 + 보드 100카드 + 시간당 50 acknowledge → broadcast/sec ~0.014 → 무시 가능. |
| R4 | **race condition: 동시 acknowledge** | lost update | 1) `acknowledge!`는 `return if acknowledged?` early-out. 2) `recompute_mention_summary!`는 idempotent. 3) lock_version 충돌 0 (update_columns). |
| R5 | **viewport tracking false-positive** | 안티 게이밍 위배 | IntersectionObserver `threshold: 0.5` + 5초 — 백그라운드 탭은 isIntersecting=false. document.visibilityState 추가 검사 필요 시 Phase 3 보강. |
| R6 | **viewer == nil broadcast** | 펄스 애니 미동작 | Phase 1은 펄스 애니 미구현이므로 무영향. Phase 3에서 per-user broadcast로 변경. |
| R7 | **MentionParserService 회귀** | 기존 멘션 알림 깨짐 | T16 회귀 테스트 + 본 Phase에서 service 자체 무수정. |
| R8 | **백필 시 부하** | 운영 시간 중 1만 건 백필 시 1분 lock | 1) `find_each(batch_size: 1000)`. 2) 새벽 시간대 실행 권고. 3) dry_run 옵션 사전 점검. |
| R9 | **카운터 캐시 drift** | UX 신뢰성 | 1) `after_commit`이 모든 Notification 변경에서 동기 호출. 2) Phase 4 `MentionSlaChecker` job이 시간당 worst_state 점검 시 같이 검증. 3) Phase 1에선 `mentions:backfill_phase1`을 정기 실행 가능. |
| R10 | **i18n** | Production 영문 환경 깨짐 | "확인", "X명 확인" 등 모두 `t(...)`로 시작. Phase 1 키: `mentions.dot_strip.acknowledged_count`, `mentions.dot_strip.acknowledge_button`. ko/en 양쪽 yml 동시 등록. |

---

## 11. 작업 의존성 그래프

```
T1 (DB) ─┬─→ T2 (Notification) ─┬─→ T3 (Order method) ─┬─→ T6 (strip partial)
         │                       │                      │
         │                       └─→ T5 (broadcast)     ├─→ T7 (dot partial)
         │                                              │
         └─────────────────────→ T4 (controller) ───────┴─→ T8 (kanban card)
                                                        │
                                T9 (mention_dots JS) ───┤
                                T10 (viewport JS) ──────┤
                                T11 (drawer button) ────┤
                                                        │
                                T12 (backfill rake) ────┤
                                                        │
                            T13/T14/T15/T16 (tests) ←───┘
                                                        │
                                T17 (real-click verify) ←┘
```

직렬 path: T1 → T2 → T3 → T6 → T8 (5 단계, ~5시간 직렬).
병렬 가능: T7/T9/T10/T11/T12은 T6 완료 후 동시 진행 가능.

---

## 12. Done Definition

본 Phase 완료 조건 (registry.json ISS-353 acceptance_criteria 9개 + spec §18 metrics):

### Acceptance Criteria 매핑

| # | Criterion | Verified by |
|---|---|---|
| 1 | notifications +5 컬럼 마이그레이션 통과 | T1 + `bin/rails db:migrate` |
| 2 | orders +5 카운터 캐시 컬럼 마이그레이션 통과 | T1 (실제 +6 — worst_state 포함) |
| 3 | Order#recompute_mention_summary! worst-state 정확 | T13 모델 테스트 |
| 4 | 멘션 있을 때만 도트 줄 렌더 | T6 첫 줄 return + T15 system test |
| 5 | 도트 5 + +N | T6 partial + T13 mention_summary_dots 테스트 |
| 6 | 미확인 우선 정렬 (○ → ◐ → ●) | T3 mention_summary_dots ORDER BY |
| 7 | [✓ 확인] 클릭 → acknowledged_at + Turbo broadcast 즉시 | T11 + T15 시나리오 B |
| 8 | IntersectionObserver 5초 → viewed_at 자동 기록 | T10 |
| 9 | 헤더 드롭다운/알림 페이지 회귀 0건 | T16 회귀 테스트 |

### spec §18 Phase 1 적용 metrics

| Metric | 측정 방법 | Phase 1 기준 |
|---|---|---|
| 명시 확인율 | acknowledged_at IS NOT NULL / total mentions | 측정 setup만 — Phase 4 대시보드에서 산출 |
| 카드 밀도 손해 | 멘션 0건 카드 평균 높이 변화 | T15에서 시각 비교, ≤5% (실제로는 0%) |
| 회귀 | 기존 알림 페이지/드롭다운 | T16 통과 |

### CPOFlow 룰 — Post-deploy real-click verification (3 ops)

T17 검증 스크립트:
1. **CREATE**: `@홍길동멘션테스트` 코멘트 작성 → 칸반 카드에 ○ 1개 + DB row + Cable 구독
2. **UPDATE**: 드로어 [✓ 확인] 클릭 → ○ → ● + acknowledged_at + 다른 사용자 화면도 갱신
3. **DELETE**: Order 삭제 → notifications dependent: :destroy + 이미 구독중인 다른 사용자 strip이 사라짐

**가장 중요한 early-verification gate**: T1 마이그레이션 직후 `bin/rails db:migrate` + `db:rollback` + `db:migrate` 양방향 통과 — 실패 시 모든 후속 작업 차단.

---

## 13. 비범위 명시 (Phase 2~5에서 처리)

명시적으로 본 Phase 1에서 **하지 않는** 작업:

- ❌ `MentionParserService` intent 파싱 (`@@`/`@@@`) — Phase 2 (ISS-354)
- ❌ SLA 자동 산출 (`assign_sla_due_at`) — Phase 2
- ❌ `MentionSlaChecker` 시간당 잡 — Phase 2
- ❌ 빨간 테두리 SLA 강조 — Phase 2 (CSS 클래스만 T7에서 미리 준비)
- ❌ 호버 개인 타임라인 카드 — Phase 3
- ❌ 펄스 애니메이션 — Phase 3
- ❌ 칼럼 헤더 합계 (🔴 N 미확인) — Phase 4
- ❌ 칸반 필터 (미확인 멘션 있음) — Phase 4
- ❌ /admin/mentions 대시보드 — Phase 4
- ❌ 안티 게이밍 (fast_acknowledge < 2s) — Phase 5
- ❌ 빠른 응답 위젯 (👍/⏳/⛔) — Phase 5

본 Phase는 **컬럼 + 도트 줄 + [✓ 확인] + 자동 viewed_at**의 4가지에만 집중 — Karpathy 단순성 원칙.

---

## 14. Summary

- **Total tasks**: 17 (T1~T17)
- **Estimated commits**: 17 (one atomic commit per task)
- **Biggest risk**: R3 — Turbo Stream broadcast load on multi-user kanban boards. 멘션-0 카드 구독 차단 + Phase 3 큐화 연기로 완화.
- **Most important early-verification gate**: T1 양방향 마이그레이션 검증 (`db:migrate` → `db:rollback` → `db:migrate`)
- **End-to-end gate**: T17 3-op 실 클릭 검증 (코멘트 @멘션 → [✓ 확인] → Order 삭제)
