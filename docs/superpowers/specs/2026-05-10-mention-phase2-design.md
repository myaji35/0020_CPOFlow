# @멘션 Phase 2 — 인텐트 파싱 + SLA + 컴포넌트 B 발신자 호버

- **작성일**: 2026-05-10
- **이슈**: ISS-354 (P0, IN_PROGRESS)
- **선행**: ISS-353 Phase 1 종결 + ISS-353-A/B 핫픽스 적용
- **후속**: ISS-355(Phase 3 호버 타임라인) → ISS-356(Phase 4 대시보드) → ISS-362(컴포넌트 A 발신자 인박스, ISS-354 의존)
- **목업 레퍼런스**: `docs/superpowers/specs/2026-05-10-mention-phase2-mockup.html`

---

## 1. 목적

Phase 1에서 모든 멘션이 동일한 `intent_level: 0` (FYI)으로 저장됐고 시각 차등이 없었음. Phase 2는 **`@` / `@@` / `@@@`을 비즈니스적 책임 강도로 인코딩**하고, 그에 따른 SLA 마감 자동 산출 + 시각 차등 + 발신자 호버 확장(컴포넌트 B)을 도입한다.

## 2. 비목표

- ❌ 발신자 인박스 통합 페이지 (`/mentions/sent`) — ISS-362 별도
- ❌ 호버 시 개인 타임라인 카드 (Phase 3)
- ❌ 펄스 애니메이션 (Phase 3)
- ❌ 칼럼 헤더 합계 / `/admin/mentions` 대시보드 (Phase 4)
- ❌ 빠른 응답 위젯 / 안티 게이밍 (Phase 5)

## 3. 핵심 결정 (5가지)

### 결정 1 — 인텐트 파싱 위치: **MentionParserService**

`MentionParserService` 한 군데에서 정규식 매칭 시 `@` 개수를 같이 캡처해서 `Notification.create!`에 `intent_level` 명시.

근거: Phase 1에 추가된 `before_validation -> { self.intent_level ||= 0 }` 훅이 fallback으로 작동하므로, 신규 멘션은 명시 set, 기존 데이터는 그대로 0 유지 — 백워드 호환.

### 결정 2 — SLA 시간: **인텐트별 고정값 (조직 룰로 추후 분리)**

| intent_level | 의미 | SLA |
|---|---|---|
| 0 | `@` FYI | **없음** (`sla_due_at = nil`) |
| 1 | `@@` 확인 필수 | **4시간** |
| 2 | `@@@` 응답 필수 | **1시간** |

Phase 2는 코드에 상수로 박음. Phase 4~ 에서 `Setting`/`Team` 단위 조정 가능하게 분리. 시간대(timezone)는 서버 `Time.current` 기준 (UTC).

### 결정 3 — SLA 마감 후 처리: **현재 시간 기반 동적 worst_state**

`Notification.sla_due_at`이 `< Time.current` AND `acknowledged_at IS NULL` → `Order#recompute_mention_summary!`의 worst-state 분기에서 `sla_overdue` 카운트. Phase 1 SQL이 이미 이 로직 포함 (`MAX(CASE WHEN sla_due_at IS NOT NULL AND sla_due_at < CURRENT_TIMESTAMP AND acknowledged_at IS NULL ...)`) → Phase 2는 **데이터만 채우면 작동**.

추가 메커니즘: 시간 경과로만 SLA 초과되는 카드를 catch-up하려면 시간당 1회 `MentionSlaChecker` Job이 필요 (Phase 1에선 이벤트 트리거가 없는 경우 worst_state 갱신이 안 됨).

### 결정 4 — 시각 차등 강도

| 상태 | Phase 1 | Phase 2 |
|---|---|---|
| `unread` | 회색 ○ | 회색 ○ (동일) |
| `viewed_only` | 노랑 ◐ | 노랑 ◐ (동일) |
| `acknowledged` | 녹색 ● | 녹색 ● (동일) |
| `sla_overdue` | (Phase 1 미사용) | **활성** — 빨간 테두리 ⊙ + **카드 좌측 4px 빨간 스트라이프** + SLA 초과 시간 표시 |

`@@@` 인텐트는 **SLA 초과 여부와 무관하게** 카드 전체에 부드러운 빨간 borderLeft. `@@`는 노란 borderLeft (Phase 2 추가).

### 결정 5 — 컴포넌트 B 발신자 호버 확장

발신자 본인이 자기 카드 도트 줄 위에 마우스 올릴 때:
- **대상자 일람** (이름/상태/봤음 시각/확인 시각/응답 시각)
- **[리마인드 모두 보내기]** 1클릭 — 미응답자 전체에 새 알림 발생
- **[개별 push]** — 한 명만 재멘션
- 발신자 ≠ 본인이면 호버 카드 비활성 (privacy)
- 호버 카드는 `position: fixed` + viewport edge 자동 보정

리마인드는 **24시간 cooldown** (스팸 방지). 같은 발신자가 같은 수신자에게 같은 카드에서 24h 이내 재 push 불가.

---

## 4. 데이터 모델 변경

Phase 1에서 컬럼은 모두 추가됐음. Phase 2는 **컬럼 추가 0** — 기존 컬럼에 데이터를 채우는 작업.

### 4.1 `Notification` — `before_validation` 훅 강화

```ruby
# Phase 1: self.intent_level ||= 0
# Phase 2: SLA 자동 산출 추가
before_validation :assign_default_intent_level
before_validation :assign_sla_due_at, on: :create

def assign_default_intent_level
  self.intent_level ||= 0
end

INTENT_SLA_HOURS = { 1 => 4, 2 => 1 }.freeze

def assign_sla_due_at
  return if sla_due_at.present?
  return unless notification_type == MENTIONED_TYPE
  hours = INTENT_SLA_HOURS[intent_level]
  self.sla_due_at = hours.hours.from_now if hours
end
```

### 4.2 `MentionParserService` — 정규식 강화

```ruby
# Phase 1: @([^]+)  → 항상 intent_level: 0
# Phase 2: (@{1,3})([^]+)  → 매칭된 @ 개수 - 1
MENTION_PATTERN_V2 = /(@{1,3})([A-Z][a-zA-Z]+(?:[ \t][A-Z][a-zA-Z]+)?|[\w가-힣]+)/.freeze

def call
  return if source_text.blank?

  # 매칭을 (prefix, name) 튜플로 — uniq는 name 기준
  matches = source_text.scan(MENTION_PATTERN_V2)  # [["@", "홍길동"], ["@@", "박과장"], ...]
  return if matches.empty?

  # 같은 사람 중복 멘션 시 강한 인텐트 우선
  by_name = {}
  matches.each do |prefix, name|
    intent = prefix.length - 1
    by_name[name] = [by_name[name] || -1, intent].max
  end

  notified_user_ids = []
  by_name.each do |name, intent_level|
    user = resolve_user(name)
    next unless user
    next if notified_user_ids.include?(user.id)
    next if user == @mentioned_by

    Notification.create!(
      user:              user,
      notifiable:        notifiable_order,
      notification_type: "mentioned",
      intent_level:      intent_level,  # ← Phase 2 추가
      title:             notification_title(intent_level),
      body:              notification_body(intent_level)
    )
    notified_user_ids << user.id
  end
end

private

def notification_title(intent)
  prefix = ["@", "@@", "@@@"][intent]
  base   = order_reference
  base ? "#{prefix}멘션: #{base}" : "#{prefix}멘션 알림"
end

def notification_body(intent)
  who = @mentioned_by.display_name
  intent_label = ["", " (확인 필수)", " (응답 필수)"][intent]
  case @subject
  when Comment then "#{who}님이 코멘트에서 회원님을 멘션했습니다#{intent_label}."
  when Task    then "#{who}님이 태스크에서 회원님을 멘션했습니다#{intent_label}."
  end
end
```

### 4.3 `MentionSlaChecker` Job — 시간 경과 catch-up

```ruby
class MentionSlaChecker < ApplicationJob
  queue_as :default

  def perform
    # 마감 직전(30분 이내) → push 1회 + 마감 초과 시점에 worst_state 갱신
    affected_orders = Notification.mentions
                                  .where("sla_due_at < ?", Time.current)
                                  .where(acknowledged_at: nil)
                                  .where(notifiable_type: "Order")
                                  .distinct
                                  .pluck(:notifiable_id)

    Order.where(id: affected_orders).find_each do |order|
      order.recompute_mention_summary!
      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_mentions",
        target:  "mention-dot-strip-#{order.id}",
        partial: "orders/mention_dot_strip",
        locals:  { order: order, viewer: nil }
      )
    end
  end
end
```

스케줄링: `solid_queue` recurring 또는 `config/recurring.yml`에 시간당 1회.

---

## 5. UI 변경

### 5.1 `_mention_dot.html.erb` — 인텐트 클래스 추가

각 도트 wrapper button에 `data-intent="<%= dot[:intent_level] %>"` 속성 추가. CSS:

```css
[data-intent="0"] [data-state="acknowledged"]  → 연한 emerald
[data-intent="1"] [data-state="acknowledged"]  → 표준 emerald
[data-intent="2"] [data-state="acknowledged"]  → 진한 emerald
```

`mention_summary_dots`가 반환하는 hash에 `:intent_level` 추가.

### 5.2 `_mention_dot_strip.html.erb` — `@` 표시 + 카드 좌측 스트라이프

- 첫 토큰 `<span>@</span>`을 worst intent에 따라 `@`/`@@`/`@@@`로 표시
- 부모 카드 `<article>`에 `data-mention-worst-intent="<%= ... %>"` 추가 → CSS로 좌측 스트라이프

```css
[data-mention-worst-intent="2"] { border-left: 4px solid #D93025; }  /* @@@ 빨강 */
[data-mention-worst-intent="1"] { border-left: 4px solid #F4A83A; }  /* @@ 노랑 */
[data-mention-worst-state="sla_overdue"] { 
  border-left: 4px solid #D93025; 
  /* (애니메이션은 Phase 3) */
}
```

worst intent는 `Order` 모델에 `mention_worst_intent` 카운터 캐시 컬럼 1개 더 추가.

### 5.3 `_mention_sender_hover.html.erb` — 컴포넌트 B 신규

```erb
<%# locals: order %>
<% return unless current_user.id == order.created_by_id  # 발신자만 %>
<% sender_mentions = order.notifications.mentions.where("notifications.created_at IN (
     SELECT MAX(created_at) FROM notifications n2
     WHERE n2.notifiable_id = ? AND n2.notifiable_type = 'Order' AND n2.notification_type = 'mentioned'
     GROUP BY n2.user_id
   )", order.id) %>

<div class="mention-sender-hover" data-mention-sender-hover>
  <h4>내가 보낸 멘션 <%= sender_mentions.count %>건</h4>
  <ul>
    <% sender_mentions.each do |n| %>
      <li>
        <%= state_icon(n) %>
        <%= n.user.display_name %>
        <span class="state-text"><%= state_label(n) %></span>
      </li>
    <% end %>
  </ul>
  <% if sender_mentions.any? { |n| n.acknowledged_at.nil? } %>
    <button data-action="click->mention-remind#sendAll">[리마인드 모두 보내기]</button>
  <% end %>
</div>
```

발신자 식별: 가장 최근 `Comment.user_id`가 멘션을 보낸 사람 — 정확하지 않은 휴리스틱이지만 Phase 2에선 충분. Phase 3+에서 `Notification`에 `sent_by_user_id` 컬럼 추가 검토.

### 5.4 `mention_dots_controller.js` — 호버 트리거

```js
// 발신자 호버 카드 토글
mouseenter(event) {
  if (!this.isSenderViewer()) return  // 본인이 발신자가 아니면 미작동
  this.fetchSenderHover(event.currentTarget)
}

mouseleave() { this.hideHover() }

isSenderViewer() {
  // 칸반 카드 상위에 data-creator-id가 있고 현재 사용자와 같은지
  const card = this.element.closest("[data-order-creator-id]")
  if (!card) return false
  return card.dataset.orderCreatorId === document.body.dataset.currentUserId
}

fetchSenderHover(triggerEl) {
  const orderId = this.element.dataset.mentionViewportOrderIdValue
  fetch(`/orders/${orderId}/mention_sender_hover`, {
    headers: { Accept: "text/html", "X-CSRF-Token": this._csrf() }
  }).then(r => r.text()).then(html => this.renderHover(html, triggerEl))
}
```

### 5.5 새 컨트롤러: `mention_remind_controller.js`

```js
sendAll(event) {
  event.preventDefault()
  const orderId = event.target.dataset.orderId
  fetch(`/orders/${orderId}/mention_remind_all`, {
    method: "POST",
    headers: { "X-CSRF-Token": this._csrf(), Accept: "text/vnd.turbo-stream.html" }
  })
}
```

서버: `POST /orders/:id/mention_remind_all` → 24h cooldown 체크 → 미응답자 전체에 새 Notification 생성 (`title: "[리마인드] @멘션: ..."`).

---

## 6. 라우트 / 컨트롤러

```ruby
# config/routes.rb
resources :orders do
  member do
    get  :mention_sender_hover     # 호버 fragment
    post :mention_remind_all       # 리마인드 일괄
    post :mention_remind/:user_id, to: 'orders#mention_remind_one'  # 개별
  end
end
```

`OrdersController`:
- `#mention_sender_hover` — 발신자 본인만 200, 아니면 403
- `#mention_remind_all` — 본인 발신 + cooldown 체크 후 N건 Notification 생성
- `#mention_remind_one` — 단일 user_id 대상

---

## 7. 컴포넌트 B 데이터 구조

`Order#sender_mention_summary` (신규):
```ruby
def sender_mention_summary(viewer:)
  return [] unless viewer&.id == created_by_id  # 발신자 본인만
  
  notifications.mentions
              .group_by(&:user_id)
              .map { |uid, group|
                latest = group.max_by(&:created_at)
                {
                  user: latest.user,
                  state: latest.acknowledged? ? :acknowledged : (latest.viewed? ? :viewed_only : :unread),
                  intent_level: latest.intent_level,
                  mentioned_at: group.min_by(&:created_at).created_at,
                  viewed_at: latest.viewed_at,
                  acknowledged_at: latest.acknowledged_at,
                  can_remind: !cooldown_active?(uid),
                  sla_overdue: latest.sla_due_at && latest.sla_due_at < Time.current && !latest.acknowledged?
                }
              }
end
```

---

## 8. i18n 키 추가

```yaml
# config/locales/ko.yml
ko:
  mentions:
    intent:
      level_0: "FYI"
      level_1: "확인 필수"
      level_2: "응답 필수"
    sla:
      remaining: "마감까지 %{time}"
      overdue: "SLA %{time} 초과"
    sender_hover:
      title: "내가 보낸 멘션 %{count}건"
      remind_all: "리마인드 모두 보내기"
      remind_one: "개별 push"
      cooldown_active: "%{user}님은 24h 이내 리마인드 발송됨"
      no_unack: "모두 확인 완료됨"

# en
en:
  mentions:
    intent:
      level_0: "FYI"
      level_1: "Acknowledge required"
      level_2: "Response required"
    sla:
      remaining: "%{time} remaining"
      overdue: "SLA overdue by %{time}"
    sender_hover:
      title: "%{count} sent mentions"
      remind_all: "Remind all"
      remind_one: "Push"
      cooldown_active: "%{user} reminded within 24h"
      no_unack: "All acknowledged"
```

---

## 9. 단계적 도입 (Wave 분할)

| Wave | 범위 | 예상 작업 |
|---|---|---|
| **Wave 1 (백엔드 코어)** | T1: MentionParserService 인텐트 파싱 / T2: Notification SLA 산출 / T3: Order#mention_worst_intent 컬럼 + recompute / T4: MentionSlaChecker Job | 4 commits |
| **Wave 2 (UI 차등)** | T5: dot 인텐트 색상 변형 / T6: 카드 좌측 스트라이프 / T7: SLA 카운트다운 표시 + i18n | 3 commits |
| **Wave 3 (컴포넌트 B)** | T8: `_mention_sender_hover` partial / T9: mention_dots_controller 호버 트리거 / T10: 라우트 + OrdersController#mention_sender_hover / T11: mention_remind_all + cooldown / T12: mention_remind_controller.js | 5 commits |
| **Wave 4 (테스트)** | T13: 모델/서비스 테스트 인텐트 / T14: SLA Job 테스트 / T15: 컨트롤러 테스트 / T16: System test 추가 (호버+리마인드) | 4 commits |

**총 예상**: 16 commits, Phase 1보다 1 적음.

---

## 10. Risk Register

| # | 리스크 | 완화 |
|---|---|---|
| R1 | 기존 `MENTION_PATTERN` 변경으로 회귀 | Phase 1 회귀 테스트 그대로 통과 + 신규 인텐트 테스트 추가 |
| R2 | SLA Job이 매시간 실행 → 부하 | `find_each` + 영향 Order만 추출, 평균 0~10건/시간 가정 |
| R3 | 카드 좌측 스트라이프 남용 → 시각 피로 | `@@`만 노랑, `@@@` 또는 `sla_overdue`만 빨강 |
| R4 | 발신자 호버 권한 누수 | 서버 `current_user.id == order.created_by_id` 체크 + 클라이언트 dataset 체크 |
| R5 | 리마인드 스팸 | 24h cooldown DB 검사 (별도 `mention_reminders` 테이블 X — 기존 Notification.created_at 활용) |
| R6 | 기존 코멘트의 `@홍길동` 백워드 호환 | 기존 매칭은 정확히 1개 `@`로 캡처 → intent_level: 0, 회귀 0 |
| R7 | Phase 1 시드/실 데이터 혼재 | 어제 ISS-353-B에서 시드 정리 완료. Phase 2 시작 전 추가 cleanup 불필요 |
| R8 | SQLite WAL 동시 sla_due_at 갱신 | 일반 update — race 없음 |
| R9 | 컴포넌트 B 호버 카드 layout 깨짐 | Phase 1 `cpoflow-mention-panel` 패턴 그대로 재사용 (body 직속 fixed) |

---

## 11. 성공 기준

| 지표 | 기준 |
|---|---|
| `@@` 멘션 SLA 준수율 | 80% 이상 (4시간 내 acknowledged) |
| 카드 시각 인지 | `@@@` SLA 초과 카드를 보드 1초 내 인지 90% (사용자 인터뷰) |
| 발신자 호버 사용 | 발신자가 자기 카드 도트 위 호버 비율 50% 이상 (analytics) |
| 리마인드 클릭률 | 미응답자 있는 카드에서 발신자 리마인드 클릭 30% 이상 |
| 회귀 | Phase 1 기능/테스트 회귀 0건 |

---

## 12. Phase 1 → Phase 2 데이터 마이그레이션

기존 멘션 데이터 (Wave 2a 시드는 ISS-353-B에서 정리됨, 이후 Sarah Johnson에게 보낸 검증 1건만 존재):
- 모두 `intent_level: 0` 유지 — 변경 없음
- `sla_due_at`은 NULL 유지 (FYI는 SLA 없음)
- 새 코멘트부터 인텐트 자동 set

마이그레이션 스크립트 불필요.

---

## 13. 종결 정의

| Acceptance | 검증 방법 |
|---|---|
| `MentionParserService`가 `@`/`@@`/`@@@`을 0/1/2로 매핑 | 단위 테스트 + e2e |
| `Notification` 생성 시 `sla_due_at` 자동 산출 (`@@`: 4h, `@@@`: 1h) | before_validation 테스트 |
| `MentionSlaChecker` Job이 시간 경과 SLA 초과 카드 worst_state 갱신 | Job 테스트 + freeze_time |
| 카드 좌측 스트라이프 — `@@` 노랑 / `@@@` or sla_overdue 빨강 | system test |
| 발신자만 호버 카드 노출 (제3자 미노출) | 컨트롤러 테스트 + system test |
| [리마인드 모두 보내기] 24h cooldown | 컨트롤러 테스트 |
| Phase 1 기능 회귀 0건 | full test suite |
| 컴포넌트 A(ISS-362)에 필요한 데이터 모델 모두 준비됨 | 데이터 의존성 점검 |
