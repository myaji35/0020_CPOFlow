# 칸반 카드 상태 범례 커스터마이즈 — 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고정 enum `Order.priority`를 사용자 편집 가능한 `CardStatus` 모델로 완전 교체하고, Settings UI에서 상태 라벨·색상·자동 배정 규칙을 편집할 수 있게 한다.

**Architecture:** DB 테이블 `card_statuses` 신설 → `orders.card_status_id` FK로 전환 → 칸반/드로어/폼/뱃지/AI 서비스가 모두 `order.card_status` 기반으로 렌더·판정. `is_system` 플래그로 삭제 불가 항목을 DB 레벨에서 보호하고, `is_default`는 부분 유니크 인덱스로 정확히 1건만 허용. 자동 배정은 `auto_rule`(JSON) + `auto_priority`를 평가하는 `CardStatus::AutoAssigner` 서비스에 캡슐화한다.

**Tech Stack:** Rails 8.1, SQLite3, TailwindCSS CDN, Stimulus (Importmap), Turbo, Solid Queue, Minitest.

**Reference spec:** `docs/superpowers/specs/2026-04-14-card-status-legend-design.md`

---

## File Structure

| 상태 | 경로 | 책임 |
|---|---|---|
| Create | `db/migrate/YYYYMMDDHHMMSS_create_card_statuses.rb` | 테이블 + 제약 + 인덱스 |
| Create | `db/migrate/YYYYMMDDHHMMSS_add_card_status_to_orders.rb` | `orders.card_status_id`, `orders.card_status_manually_set_at` |
| Create | `db/migrate/YYYYMMDDHHMMSS_backfill_orders_card_status.rb` | 기존 `priority` → `card_status_id` 이관 |
| Create | `db/migrate/YYYYMMDDHHMMSS_drop_orders_priority.rb` | `orders.priority` 컬럼 제거 |
| Create | `app/models/card_status.rb` | 모델, `deletable?`, `default`, scope |
| Create | `lib/card_status_color_presets.rb` | 팔레트 12개 상수 |
| Create | `db/seeds/card_statuses.rb` | 7개 초기 프리셋 |
| Modify | `db/seeds.rb` | 위 seed 파일 require |
| Create | `app/services/card_status/auto_assigner.rb` | 규칙 평가 서비스 |
| Create | `app/jobs/card_status_auto_assign_job.rb` | 일간 배치 |
| Modify | `app/models/order.rb` | enum 제거, `belongs_to :card_status`, `urgent_unassigned?` 재작성, 콜백 |
| Modify | `app/services/gmail/email_to_order_service.rb:47,176-186` | `infer_priority` → `CardStatus::AutoAssigner.for_due_date(due)` |
| Modify | `app/helpers/application_helper.rb:44-47` | `priority_badge` → `card_status_badge` |
| Modify | `app/views/kanban/_card.html.erb` | 하드코딩 색상 제거, `order.card_status.bg_color/border_color/text_color` 사용 |
| Modify | `app/views/kanban/index.html.erb` | 범례 필터 버튼 동적 렌더, `data-card-status-key` |
| Modify | `app/views/orders/_drawer_content.html.erb:49-73` | priority 드롭다운 → card_status 드롭다운 |
| Modify | `app/views/orders/_form.html.erb:173-175` | `Order.priorities.keys` → `CardStatus.ordered.pluck(:name, :id)` |
| Modify | `app/views/orders/_sidebar_panel.html.erb:49` | badge 헬퍼 교체 |
| Modify | `app/views/orders/index.html.erb:144` | `case order.priority` → `order.card_status.key` |
| Modify | `app/views/orders/pdf/purchase_order.html.erb:34`, `pdf/quote.html.erb:28` | 동일 교체 |
| Modify | `app/controllers/orders_controller.rb` strong params | `:priority` → `:card_status_id` |
| Create | `app/controllers/settings/card_statuses_controller.rb` | CRUD + reorder + inline_rename |
| Create | `app/views/settings/card_statuses/index.html.erb` | 리스트 + 드래그 |
| Create | `app/views/settings/card_statuses/_row.html.erb` | 한 줄 partial (turbo-stream 친화) |
| Create | `app/views/settings/card_statuses/_edit_modal.html.erb` | 편집 모달 |
| Create | `app/javascript/controllers/card_status_preview_controller.js` | Stimulus 실시간 미리보기 |
| Create | `app/javascript/controllers/card_status_sortable_controller.js` | Stimulus 드래그 재정렬 |
| Modify | `config/routes.rb:203-219` | `resources :card_statuses` + custom routes |
| Modify | `app/views/settings/base/index.html.erb` | "칸반 상태 관리" 메뉴 카드 추가 |
| Create | `test/models/card_status_test.rb` | 모델 유닛 |
| Create | `test/services/card_status/auto_assigner_test.rb` | 규칙 평가 |
| Create | `test/controllers/settings/card_statuses_controller_test.rb` | CRUD |
| Create | `test/system/card_status_management_test.rb` | 시스템 (Capybara) |
| Modify | `test/models/order_test.rb` | priority 테스트 → card_status |
| Modify | `test/fixtures/orders.yml` | `card_status: normal` fixture 추가 |
| Create | `test/fixtures/card_statuses.yml` | 7개 프리셋 fixture |

---

## Task 1: CardStatus 모델 + 테이블 생성

**Files:**
- Create: `db/migrate/20260414120001_create_card_statuses.rb`
- Create: `lib/card_status_color_presets.rb`
- Create: `app/models/card_status.rb`
- Create: `test/fixtures/card_statuses.yml`
- Test: `test/models/card_status_test.rb`

- [ ] **Step 1.1: 팔레트 상수 작성**

Create `lib/card_status_color_presets.rb`:
```ruby
# frozen_string_literal: true

# 12개 색상 프리셋 — Settings 편집 모달에서 원클릭 선택 지원.
# 각 세트는 {key, name, bg, border, text} 구조 (bg/border/text는 HEX #RRGGBB).
module CardStatusColorPresets
  ALL = [
    { key: "gray",   name: "회색",   bg: "#FAFAFA", border: "#E5E7EB", text: "#374151" },
    { key: "red",    name: "빨강",   bg: "#FFF1F2", border: "#FECDD3", text: "#991B1B" },
    { key: "orange", name: "주황",   bg: "#FFF7ED", border: "#FED7AA", text: "#9A3412" },
    { key: "amber",  name: "황색",   bg: "#FEFCE8", border: "#FEF08A", text: "#854D0E" },
    { key: "green",  name: "초록",   bg: "#F0FDF4", border: "#BBF7D0", text: "#14532D" },
    { key: "teal",   name: "청록",   bg: "#F0FDFA", border: "#99F6E4", text: "#134E4A" },
    { key: "blue",   name: "파랑",   bg: "#EFF6FF", border: "#BFDBFE", text: "#1E3A8A" },
    { key: "indigo", name: "남색",   bg: "#EEF2FF", border: "#C7D2FE", text: "#312E81" },
    { key: "purple", name: "보라",   bg: "#F5F3FF", border: "#DDD6FE", text: "#5B21B6" },
    { key: "pink",   name: "분홍",   bg: "#FDF2F8", border: "#FBCFE8", text: "#9D174D" },
    { key: "brown",  name: "갈색",   bg: "#FAF5EF", border: "#E7D3B8", text: "#6B3F00" },
    { key: "slate",  name: "진회색", bg: "#F1F5F9", border: "#CBD5E1", text: "#1E293B" }
  ].freeze

  def self.find(key)
    ALL.find { |p| p[:key] == key.to_s }
  end
end
```

- [ ] **Step 1.2: 마이그레이션 작성**

Create `db/migrate/20260414120001_create_card_statuses.rb`:
```ruby
class CreateCardStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :card_statuses do |t|
      t.string  :key,          null: false
      t.string  :name,         null: false
      t.string  :bg_color,     null: false, limit: 7
      t.string  :border_color, null: false, limit: 7
      t.string  :text_color,   null: false, limit: 7
      t.integer :position,     null: false, default: 0
      t.boolean :is_system,    null: false, default: false
      t.boolean :is_default,   null: false, default: false
      t.text    :auto_rule                                   # JSON string, SQLite에는 jsonb 없음
      t.integer :auto_priority, null: false, default: 0
      t.timestamps
    end

    add_index :card_statuses, :key,      unique: true
    add_index :card_statuses, :position
    # SQLite partial unique: is_default=1 인 레코드 최대 1건 보장
    add_index :card_statuses, :is_default,
              unique: true,
              where:  "is_default = 1",
              name:   "index_card_statuses_on_single_default"
  end
end
```

- [ ] **Step 1.3: 실패 테스트 작성**

Create `test/models/card_status_test.rb`:
```ruby
require "test_helper"

class CardStatusTest < ActiveSupport::TestCase
  test "valid factory" do
    cs = CardStatus.new(
      key: "manual_test", name: "수동",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827",
      position: 99
    )
    assert cs.valid?, cs.errors.full_messages.inspect
  end

  test "key unique" do
    CardStatus.create!(
      key: "dup", name: "중복1",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    dup = CardStatus.new(
      key: "dup", name: "중복2",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_not dup.valid?
    assert_includes dup.errors[:key], "has already been taken"
  end

  test "hex color format required" do
    cs = CardStatus.new(
      key: "badcolor", name: "bad",
      bg_color: "red", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_not cs.valid?
    assert_includes cs.errors[:bg_color].join, "format"
  end

  test "only one default allowed" do
    CardStatus.create!(
      key: "default_a", name: "A", is_default: true,
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_raises(ActiveRecord::RecordNotUnique) do
      CardStatus.create!(
        key: "default_b", name: "B", is_default: true,
        bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
      )
    end
  end

  test "deletable? returns false for system" do
    cs = CardStatus.create!(
      key: "sys_x", name: "sys", is_system: true,
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert_not cs.deletable?
  end

  test "deletable? returns true when no orders use it" do
    cs = CardStatus.create!(
      key: "free_x", name: "free",
      bg_color: "#FFFFFF", border_color: "#E5E7EB", text_color: "#111827"
    )
    assert cs.deletable?
  end

  test "default scope returns the is_default record" do
    skip "orders fixture 포함된 Task 2 이후 검증"
  end
end
```

- [ ] **Step 1.4: 테스트 실행 (실패 확인)**

Run: `bin/rails db:migrate:redo 2>/dev/null; bin/rails test test/models/card_status_test.rb 2>&1 | tail -20`
Expected: FAIL with "Unknown constant CardStatus" 또는 migration not yet run

- [ ] **Step 1.5: 모델 작성**

Create `app/models/card_status.rb`:
```ruby
# frozen_string_literal: true

class CardStatus < ApplicationRecord
  HEX_COLOR = /\A#[0-9A-Fa-f]{6}\z/.freeze

  has_many :orders, dependent: :restrict_with_error

  validates :key,          presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name,         presence: true, length: { maximum: 40 }
  validates :bg_color,     :border_color, :text_color,
                           presence: true, format: { with: HEX_COLOR, message: "must be #RRGGBB format" }
  validates :auto_priority, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :id) }

  def self.default
    find_by(is_default: true) || ordered.first
  end

  def deletable?
    !is_system? && orders.empty?
  end

  # auto_rule JSON 파싱 (예: {"when":"due_date","operator":"lte","value":3})
  def parsed_auto_rule
    return nil if auto_rule.blank?
    JSON.parse(auto_rule)
  rescue JSON::ParserError
    nil
  end

  # 현재 Order에 이 상태의 auto_rule이 적용되는지 판정
  def auto_applies_to?(order)
    rule = parsed_auto_rule
    return false unless rule
    case rule["when"]
    when "due_date"
      return false unless order.due_date
      days = (order.due_date - Date.current).to_i
      case rule["operator"]
      when "lte" then days <= rule["value"].to_i
      when "gte" then days >= rule["value"].to_i
      else false
      end
    else
      false
    end
  end
end
```

- [ ] **Step 1.6: 마이그레이션 실행 + 테스트 재실행**

Run:
```
bin/rails db:migrate
bin/rails test test/models/card_status_test.rb
```
Expected: 6 tests, 0 failures (1 skipped)

- [ ] **Step 1.7: Fixture 작성**

Create `test/fixtures/card_statuses.yml`:
```yaml
normal:
  key: normal
  name: 보통
  bg_color: "#FAFAFA"
  border_color: "#E5E7EB"
  text_color: "#374151"
  position: 3
  is_system: true
  is_default: true
  auto_priority: 0

urgent:
  key: urgent
  name: 긴급
  bg_color: "#FFF1F2"
  border_color: "#FECDD3"
  text_color: "#991B1B"
  position: 1
  is_system: true
  is_default: false
  auto_rule: '{"when":"due_date","operator":"lte","value":3}'
  auto_priority: 30

high:
  key: high
  name: 높음
  bg_color: "#FFF7ED"
  border_color: "#FED7AA"
  text_color: "#9A3412"
  position: 2
  is_system: true
  is_default: false
  auto_rule: '{"when":"due_date","operator":"lte","value":7}'
  auto_priority: 20
```

- [ ] **Step 1.8: 커밋**

```bash
git add db/migrate/20260414120001_create_card_statuses.rb \
        lib/card_status_color_presets.rb \
        app/models/card_status.rb \
        test/models/card_status_test.rb \
        test/fixtures/card_statuses.yml
git commit -m "feat(card-status): CardStatus 모델 + 테이블 + 팔레트 상수 추가"
```

---

## Task 2: orders에 card_status_id FK 추가 + 데이터 이관

**Files:**
- Create: `db/migrate/20260414120002_add_card_status_to_orders.rb`
- Create: `db/seeds/card_statuses.rb`
- Modify: `db/seeds.rb`
- Create: `db/migrate/20260414120003_backfill_orders_card_status.rb`
- Modify: `test/fixtures/orders.yml`

- [ ] **Step 2.1: FK 컬럼 마이그레이션**

Create `db/migrate/20260414120002_add_card_status_to_orders.rb`:
```ruby
class AddCardStatusToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :card_status, foreign_key: true, null: true, index: true
    add_column    :orders, :card_status_manually_set_at, :datetime, null: true
    add_index     :orders, :card_status_manually_set_at
  end
end
```

- [ ] **Step 2.2: 7개 프리셋 seed 작성**

Create `db/seeds/card_statuses.rb`:
```ruby
# frozen_string_literal: true

# 7개 샘플 프리셋 — 스펙 §4 표와 동일
PRESETS = [
  { key: "urgent",  name: "긴급",     bg: "#FFF1F2", border: "#FECDD3", text: "#991B1B",
    position: 1, is_system: true,  is_default: false,
    auto_rule: { when: "due_date", operator: "lte", value: 3 }, auto_priority: 30 },
  { key: "high",    name: "높음",     bg: "#FFF7ED", border: "#FED7AA", text: "#9A3412",
    position: 2, is_system: true,  is_default: false,
    auto_rule: { when: "due_date", operator: "lte", value: 7 }, auto_priority: 20 },
  { key: "normal",  name: "보통",     bg: "#FAFAFA", border: "#E5E7EB", text: "#374151",
    position: 3, is_system: true,  is_default: true,
    auto_rule: nil, auto_priority: 0 },
  { key: "low",     name: "낮음",     bg: "#F0FDF4", border: "#BBF7D0", text: "#14532D",
    position: 4, is_system: true,  is_default: false,
    auto_rule: nil, auto_priority: 0 },
  { key: "vip",     name: "VIP 고객", bg: "#F5F3FF", border: "#DDD6FE", text: "#5B21B6",
    position: 5, is_system: false, is_default: false,
    auto_rule: nil, auto_priority: 0 },
  { key: "hold",    name: "대기/보류", bg: "#FEFCE8", border: "#FEF08A", text: "#854D0E",
    position: 6, is_system: false, is_default: false,
    auto_rule: nil, auto_priority: 0 },
  { key: "overdue", name: "기한초과", bg: "#FEE2E2", border: "#FCA5A5", text: "#7F1D1D",
    position: 7, is_system: false, is_default: false,
    auto_rule: { when: "due_date", operator: "lte", value: 0 }, auto_priority: 40 }
].freeze

PRESETS.each do |p|
  cs = CardStatus.find_or_initialize_by(key: p[:key])
  cs.assign_attributes(
    name:          p[:name],
    bg_color:      p[:bg],
    border_color:  p[:border],
    text_color:    p[:text],
    position:      p[:position],
    is_system:     p[:is_system],
    is_default:    p[:is_default],
    auto_rule:     p[:auto_rule]&.to_json,
    auto_priority: p[:auto_priority]
  )
  cs.save!
end
puts "[seed] CardStatus: #{CardStatus.count}개 seeded"
```

- [ ] **Step 2.3: `db/seeds.rb`에 require 추가**

Modify `db/seeds.rb` — 파일 맨 아래에 추가:
```ruby
load Rails.root.join("db/seeds/card_statuses.rb")
```

- [ ] **Step 2.4: 기존 priority → card_status_id 이관 마이그레이션**

Create `db/migrate/20260414120003_backfill_orders_card_status.rb`:
```ruby
class BackfillOrdersCardStatus < ActiveRecord::Migration[8.1]
  def up
    # 반드시 seed 먼저 실행됐다고 가정 (프로덕션에서 rails db:seed 후 rails db:migrate 순서)
    # 방어적으로 여기서도 7개 프리셋이 있는지 확인하고 없으면 로드
    if CardStatus.count < 7
      load Rails.root.join("db/seeds/card_statuses.rb")
    end

    mapping = {
      "urgent" => CardStatus.find_by!(key: "urgent").id,
      "high"   => CardStatus.find_by!(key: "high").id,
      "medium" => CardStatus.find_by!(key: "normal").id,
      "low"    => CardStatus.find_by!(key: "low").id
    }

    mapping.each do |legacy, new_id|
      execute "UPDATE orders SET card_status_id = #{new_id} WHERE priority = #{priority_value(legacy)} AND card_status_id IS NULL"
    end

    # 그래도 남은 것은 default(normal)로
    normal_id = CardStatus.find_by!(key: "normal").id
    execute "UPDATE orders SET card_status_id = #{normal_id} WHERE card_status_id IS NULL"
  end

  def down
    execute "UPDATE orders SET card_status_id = NULL"
  end

  private

  def priority_value(key)
    { "low" => 0, "medium" => 1, "high" => 2, "urgent" => 3 }[key]
  end
end
```

- [ ] **Step 2.5: orders fixture에 card_status 추가**

Modify `test/fixtures/orders.yml` — 모든 엔트리에 다음 줄 추가 (아직 priority 컬럼은 남아 있으므로 양쪽 유지):
```yaml
# 예: 기존 fixture이 다음과 같다면
# one:
#   title: "Test Order"
#   customer_name: "Acme"
#   priority: 1
# 다음과 같이 card_status 참조 추가:
one:
  title: "Test Order"
  customer_name: "Acme"
  priority: 1
  card_status: normal   # ← 추가
```

> 주의: fixture가 존재하는 모든 엔트리에 `card_status: normal` 한 줄 추가한다. 어떤 엔트리가 있는지는 `grep -c "^[a-z_]*:$" test/fixtures/orders.yml`로 확인 후 전부 수정.

- [ ] **Step 2.6: 마이그레이션 + seed + 테스트 실행**

Run:
```
bin/rails db:migrate
bin/rails db:seed
bin/rails test test/models/card_status_test.rb
```
Expected: CardStatus 7건 seeded, 테스트 모두 통과

- [ ] **Step 2.7: 커밋**

```bash
git add db/migrate/20260414120002_add_card_status_to_orders.rb \
        db/migrate/20260414120003_backfill_orders_card_status.rb \
        db/seeds/card_statuses.rb \
        db/seeds.rb \
        test/fixtures/orders.yml
git commit -m "feat(card-status): orders.card_status_id 추가 + 프리셋 seed + 데이터 이관"
```

---

## Task 3: AutoAssigner 서비스 + 테스트

**Files:**
- Create: `app/services/card_status/auto_assigner.rb`
- Test: `test/services/card_status/auto_assigner_test.rb`

- [ ] **Step 3.1: 실패 테스트 작성**

Create `test/services/card_status/auto_assigner_test.rb`:
```ruby
require "test_helper"

class CardStatus::AutoAssignerTest < ActiveSupport::TestCase
  setup do
    # 최소 3개: urgent(lte 3), high(lte 7), normal(default)
    @urgent = card_statuses(:urgent)
    @high   = card_statuses(:high)
    @normal = card_statuses(:normal)
  end

  test "returns urgent when due within 3 days" do
    order = Order.new(due_date: Date.current + 2)
    result = CardStatus::AutoAssigner.call(order)
    assert_equal @urgent, result
  end

  test "returns high when due within 7 days but not 3" do
    order = Order.new(due_date: Date.current + 5)
    assert_equal @high, CardStatus::AutoAssigner.call(order)
  end

  test "returns default(normal) when no rule matches" do
    order = Order.new(due_date: Date.current + 30)
    assert_equal @normal, CardStatus::AutoAssigner.call(order)
  end

  test "returns default when due_date nil" do
    order = Order.new(due_date: nil)
    assert_equal @normal, CardStatus::AutoAssigner.call(order)
  end

  test "higher auto_priority wins when multiple rules match" do
    # urgent(30) vs high(20): due 2일이면 둘 다 매칭, urgent 우선
    order = Order.new(due_date: Date.current + 2)
    assert_equal @urgent, CardStatus::AutoAssigner.call(order)
  end
end
```

- [ ] **Step 3.2: 서비스 작성**

Create `app/services/card_status/auto_assigner.rb`:
```ruby
# frozen_string_literal: true

module CardStatus::Module
  # 네임스페이스 conflict 방지용 dummy — 아래 클래스가 진짜 구현
end

class CardStatus
  class AutoAssigner
    # Order 하나를 받아 적절한 CardStatus를 반환.
    # auto_rule 있는 것 중 auto_priority 내림차순으로 평가, 첫 매칭 반환.
    # 매칭 없으면 CardStatus.default.
    def self.call(order)
      candidates = CardStatus.where.not(auto_rule: nil).order(auto_priority: :desc)
      match = candidates.find { |cs| cs.auto_applies_to?(order) }
      match || CardStatus.default
    end

    # due_date만 주어졌을 때 Service helper (Gmail 파이프라인 등 Order 객체 없이 평가용)
    def self.for_due_date(due_date)
      call(Order.new(due_date: due_date))
    end
  end
end
```

- [ ] **Step 3.3: 테스트 실행**

Run: `bin/rails test test/services/card_status/auto_assigner_test.rb`
Expected: 5 tests, 0 failures

- [ ] **Step 3.4: 커밋**

```bash
git add app/services/card_status/auto_assigner.rb \
        test/services/card_status/auto_assigner_test.rb
git commit -m "feat(card-status): AutoAssigner 서비스 — 규칙 기반 자동 배정"
```

---

## Task 4: Order 모델 전환 + 콜백

**Files:**
- Modify: `app/models/order.rb` (enum 제거, belongs_to, 콜백)
- Modify: `test/models/order_test.rb` (priority 참조 제거)

- [ ] **Step 4.1: Order 모델 수정**

Modify `app/models/order.rb` — 다음 변경을 적용:

**A. enum priority 블록 제거 (41-46행)**:
```ruby
# 삭제:
#   enum :priority, {
#     low: 0, medium: 1, high: 2, urgent: 3
#   }, default: :medium
```

**B. 연관 추가 (enum 삭제 자리에)**:
```ruby
  belongs_to :card_status, optional: true

  # 기본값 보장: 새 Order는 default(normal)로 시작
  before_validation :ensure_card_status, on: :create

  # 저장 후 자동 배정: 수동 지정 없으면 규칙 재평가
  after_save :maybe_auto_assign_card_status, if: :should_auto_reassign?
```

**C. `urgent` scope 및 `urgent_unassigned?` 재작성** (order.rb 59행, 97-99행 부근):

기존:
```ruby
  scope :urgent, -> { where("due_date <= ?", 7.days.from_now).where.not(status: [ :get_grn, :give_up, :done ]) }
```

대체:
```ruby
  scope :urgent, -> {
    urgent_keys = %w[urgent high overdue]
    joins(:card_status).where(card_statuses: { key: urgent_keys })
                       .where.not(status: [ :get_grn, :give_up, :done ])
  }
```

`urgent_unassigned?` 메서드 재작성 (기존 `return false unless %w[urgent high].include?(priority.to_s)` 부분):
```ruby
  def urgent_unassigned?
    return false unless card_status
    %w[urgent high overdue].include?(card_status.key) &&
      assignees.empty? &&
      due_date.present? &&
      due_date <= Date.current
  end
```

**D. 색상·라벨 헬퍼 메서드** (뷰에서 반복 호출 편하게):
```ruby
  def card_bg_color;     card_status&.bg_color     || "#FAFAFA"; end
  def card_border_color; card_status&.border_color || "#E5E7EB"; end
  def card_text_color;   card_status&.text_color   || "#374151"; end
```

**E. 콜백 메서드 (private 구간에 추가)**:
```ruby
  private

  def ensure_card_status
    self.card_status ||= CardStatus.default
  end

  def should_auto_reassign?
    # 수동 배정된 건 존중, 그 외에는 due_date 변경 시 재평가
    card_status_manually_set_at.blank? && (saved_change_to_due_date? || saved_change_to_card_status_id?)
  end

  def maybe_auto_assign_card_status
    target = CardStatus::AutoAssigner.call(self)
    return if target.id == card_status_id
    update_column(:card_status_id, target.id)
  end
```

**F. 151, 173-181, 99행 부근의 `priority` 문자열 참조 제거 또는 `card_status.key`로 대체** — 정확한 위치는 `grep -n 'priority' app/models/order.rb` 결과에 따라.

> 주의: `priority_badge` 헬퍼는 Task 5에서 교체, order.rb의 `priority` enum 정의 제거로 인한 컴파일 에러만 먼저 잡는다. `column :priority` 자체는 아직 DB에 남아 있으므로 모델이 로드되는 것은 문제 없음.

- [ ] **Step 4.2: Order 기존 테스트 업데이트**

Modify `test/models/order_test.rb` — `priority: :urgent` 사용 라인을 `card_status: card_statuses(:urgent)` 로 교체. 구체적으로 바꿀 라인 전부 찾으려면:
```
grep -n "priority:\s*:" test/models/order_test.rb
```

각 매칭 라인을 `card_status: card_statuses(:<key>)` 형태로 교체.

- [ ] **Step 4.3: 테스트 실행**

Run:
```
bin/rails test test/models/order_test.rb test/models/card_status_test.rb test/services/card_status/auto_assigner_test.rb
```
Expected: 모두 pass.

- [ ] **Step 4.4: 커밋**

```bash
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat(card-status): Order 모델을 CardStatus FK 기반으로 전환 + 자동 배정 콜백"
```

---

## Task 5: 뷰/헬퍼 교체 (칸반, 드로어, 폼, PDF)

**Files:**
- Modify: `app/helpers/application_helper.rb:44-47`
- Modify: `app/views/kanban/_card.html.erb`
- Modify: `app/views/kanban/index.html.erb`
- Modify: `app/views/orders/_drawer_content.html.erb:49-73`
- Modify: `app/views/orders/_form.html.erb:173-175`
- Modify: `app/views/orders/_sidebar_panel.html.erb:49`
- Modify: `app/views/orders/index.html.erb:144`
- Modify: `app/views/orders/pdf/purchase_order.html.erb:34`
- Modify: `app/views/orders/pdf/quote.html.erb:28`
- Modify: `app/controllers/orders_controller.rb` (strong params)

- [ ] **Step 5.1: `application_helper.rb` 뱃지 헬퍼 교체**

기존 `PRIORITY_COLORS` 상수와 `priority_badge` 메서드 삭제, 아래 대체:
```ruby
  def card_status_badge(order)
    cs = order.card_status
    return "".html_safe unless cs
    content_tag(:span, cs.name,
                class: "text-xs font-semibold px-2 py-0.5 rounded-full",
                style: "background:#{cs.text_color}; color:white")
  end

  # 호환 wrapper — 기존 호출 코드가 점진 전환될 때까지 유지 (다음 리팩터 때 제거)
  alias_method :priority_badge, :card_status_badge
```

- [ ] **Step 5.2: `_card.html.erb` 색상 로직 단순화**

Replace lines 1-16:
```erb
<%
  card_bg_style     = "background-color:#{order.card_bg_color};"
  card_border_style = "border-color:#{order.card_border_color};"
  card_text_style   = "color:#{order.card_text_color};"
%>
<div class="relative rounded-lg border p-3 shadow-sm hover:shadow-md hover:border-[#00A1E0] transition-all group cursor-pointer<%= ' ring-2 ring-[#D93025] ring-offset-1' if order.critical? %>"
     style="<%= card_bg_style %> <%= card_border_style %> <%= card_text_style %>"
     data-order-id="<%= order.id %>"
     data-card-status-key="<%= order.card_status&.key %>"
     data-card-status-id="<%= order.card_status_id %>"
     data-due-days="<%= order.days_until_due.to_i %>"
     data-assignee-ids="<%= order.assignees.map(&:id).join(',') %>"
     data-title="<%= order.title %>"
     data-customer="<%= order.customer_name %>"
     data-refno="<%= order.reference_no %>"
```

- [ ] **Step 5.3: `kanban/index.html.erb` 필터 버튼 동적 렌더**

Replace static priority filter buttons around line 32 with:
```erb
<% CardStatus.ordered.each do |cs| %>
  <button class="filter-priority-btn px-2.5 py-1.5 bg-white dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors border-r border-gray-200 dark:border-gray-600 last:border-0"
          data-filter-key="<%= cs.key %>"
          style="--badge-color: <%= cs.bg_color %>">
    <span class="inline-block w-2 h-2 rounded-full mr-1 align-middle" style="background-color: <%= cs.text_color %>"></span>
    <%= cs.name %>
  </button>
<% end %>
```

그리고 JS 필터 로직 (658행)의 `card.dataset.priority` 참조를 `card.dataset.cardStatusKey`로, 버튼 데이터 속성도 `activePriority` → `activeStatusKey` 변수명만 조정 (동작 로직은 동일).

- [ ] **Step 5.4: `_drawer_content.html.erb` 드롭다운 전환**

`priority-dropdown-*` 영역 (49-73행)을 다음으로 교체:
```erb
<div class="relative inline-block" id="card-status-dropdown-<%= order.id %>">
  <button type="button"
          onclick="toggleDropdown('card-status-menu-<%= order.id %>')"
          class="flex items-center gap-1 hover:opacity-80">
    <%= card_status_badge(order) %>
  </button>
  <div id="card-status-menu-<%= order.id %>"
       class="hidden absolute left-0 mt-1 w-40 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded shadow-lg z-30">
    <% CardStatus.ordered.each do |cs| %>
      <%= form_with model: order, url: order_path(order), method: :patch, local: true do |f| %>
        <%= f.hidden_field :card_status_id, value: cs.id %>
        <%= f.hidden_field :card_status_manually_set_at, value: Time.current.iso8601 %>
        <button type="submit" class="w-full text-left px-3 py-1.5 text-sm hover:bg-gray-50 dark:hover:bg-gray-700
                                     <%= order.card_status_id == cs.id ? 'font-semibold text-primary' : 'text-gray-700 dark:text-gray-300' %>">
          <%= cs.name %>
          <% if order.card_status_id == cs.id %><span class="float-right">✓</span><% end %>
        </button>
      <% end %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5.5: `_form.html.erb` select 필드 교체**

Replace lines 173-175:
```erb
<%= f.label :card_status_id, "상태", class: "block text-xs font-semibold text-gray-600 mb-1.5" %>
<%= f.select :card_status_id,
             CardStatus.ordered.pluck(:name, :id),
             { selected: order.card_status_id || CardStatus.default&.id },
             class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm text-gray-900 bg-white focus:outline-none focus:border-[#00A1E0] focus:ring-1 focus:ring-[#00A1E0]" %>
```

- [ ] **Step 5.6: 나머지 뷰의 `priority` 참조 일괄 교체**

각 파일에서:
- `order.priority` → `order.card_status&.key`
- `@order.priority` → `@order.card_status&.key`
- `priority_badge(order)` → `card_status_badge(order)` (alias로 당장은 돌아가지만 점진 교체)
- `case order.priority ... when "urgent" ...` 스타일은 `case order.card_status&.key`로

구체 위치:
- `app/views/orders/index.html.erb:144`
- `app/views/orders/pdf/purchase_order.html.erb:34`
- `app/views/orders/pdf/quote.html.erb:28`
- `app/views/orders/_sidebar_panel.html.erb:49` → `card_status_badge(order)`로

- [ ] **Step 5.7: `orders_controller.rb` strong params**

`order_params` 메서드에서 `:priority` 제거, `:card_status_id, :card_status_manually_set_at` 추가.

- [ ] **Step 5.8: 수동 해제 링크 추가 (드로어 하단)**

`_drawer_content.html.erb`의 드롭다운 아래에:
```erb
<% if order.card_status_manually_set_at.present? %>
  <%= form_with model: order, url: order_path(order), method: :patch, local: true, class: "inline" do |f| %>
    <%= f.hidden_field :card_status_manually_set_at, value: "" %>
    <%= f.submit "🔄 자동 배정으로 되돌리기", class: "text-xs text-gray-500 underline cursor-pointer bg-transparent border-0 p-0" %>
  <% end %>
<% end %>
```

> 컨트롤러 update 액션에서 빈 문자열 "" → nil 정규화가 필요하면 strong params 다음에 `params[:order][:card_status_manually_set_at] = nil if params.dig(:order, :card_status_manually_set_at) == ""` 추가.

- [ ] **Step 5.9: 서버 기동 확인**

Run: `bin/rails server -p 3001 -d && sleep 3 && curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3001/kanban ; kill $(lsof -ti:3001)`
Expected: 302 (로그인 리다이렉트) 또는 200

- [ ] **Step 5.10: 커밋**

```bash
git add app/helpers/application_helper.rb \
        app/views/kanban/ app/views/orders/ \
        app/controllers/orders_controller.rb
git commit -m "feat(card-status): 뷰·헬퍼·strong params 전환"
```

---

## Task 6: Gmail 파이프라인 priority 제거

**Files:**
- Modify: `app/services/gmail/email_to_order_service.rb:47,176-186`

- [ ] **Step 6.1: `email_to_order_service.rb` 수정**

Line 47 (attributes에 `priority: infer_priority` 부분):
```ruby
# 삭제:
#   priority: infer_priority,
```
로 삭제. Order 생성 후 `after_save` 콜백(`maybe_auto_assign_card_status`)이 자동으로 `card_status_id`를 채운다 (`ensure_card_status`로 default가 먼저 들어가고, due_date가 있으면 after_save에서 규칙 적용).

그리고 `infer_priority` 메서드(176-186행) 전체 삭제.

- [ ] **Step 6.2: 회귀 테스트**

Run: `bin/rails test test/services/gmail/ test/models/order_test.rb`
Expected: 모두 pass

- [ ] **Step 6.3: 커밋**

```bash
git add app/services/gmail/email_to_order_service.rb
git commit -m "feat(card-status): Gmail 파이프라인의 priority 배정 제거 → AutoAssigner로 일원화"
```

---

## Task 7: Settings 컨트롤러 + 라우트

**Files:**
- Modify: `config/routes.rb:203-219`
- Create: `app/controllers/settings/card_statuses_controller.rb`
- Test: `test/controllers/settings/card_statuses_controller_test.rb`

- [ ] **Step 7.1: 라우트 추가**

Modify `config/routes.rb` — `namespace :settings` 블록 안에 추가:
```ruby
    resources :card_statuses, except: %i[show new edit] do
      collection { patch :reorder }
      member     { patch :inline_rename }
    end
```

Run: `bin/rails routes -g card_statuses` to confirm.

- [ ] **Step 7.2: 실패 테스트 작성**

Create `test/controllers/settings/card_statuses_controller_test.rb`:
```ruby
require "test_helper"

class Settings::CardStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user if respond_to?(:sign_in)  # devise test helper
  end

  test "GET index" do
    get settings_card_statuses_path
    assert_response :success
    assert_select "h1", /상태/
  end

  test "POST create valid" do
    assert_difference -> { CardStatus.count }, 1 do
      post settings_card_statuses_path, params: {
        card_status: {
          key: "new_manual", name: "새 상태",
          bg_color: "#EEF2FF", border_color: "#C7D2FE", text_color: "#312E81"
        }
      }
    end
    assert_redirected_to settings_card_statuses_path
  end

  test "POST create invalid returns 422" do
    post settings_card_statuses_path, params: {
      card_status: { key: "", name: "" }
    }
    assert_response :unprocessable_entity
  end

  test "PATCH update (rename inline)" do
    cs = card_statuses(:vip)
    patch inline_rename_settings_card_status_path(cs), params: { name: "새VIP" }
    assert_response :success
    assert_equal "새VIP", cs.reload.name
  end

  test "DELETE destroy blocks system" do
    cs = card_statuses(:urgent)
    assert_no_difference -> { CardStatus.count } do
      delete settings_card_status_path(cs)
    end
    assert_response :unprocessable_entity
  end

  test "DELETE destroy blocks in-use" do
    cs = card_statuses(:vip)
    Order.create!(
      title: "X", customer_name: "A", card_status: cs,
      status: "new_rfq"
    )
    assert_no_difference -> { CardStatus.count } do
      delete settings_card_status_path(cs)
    end
    assert_response :unprocessable_entity
  end

  test "DELETE destroy succeeds when deletable" do
    cs = card_statuses(:hold)
    cs.orders.destroy_all
    assert_difference -> { CardStatus.count }, -1 do
      delete settings_card_status_path(cs)
    end
    assert_redirected_to settings_card_statuses_path
  end

  test "PATCH reorder accepts array" do
    ids = CardStatus.ordered.pluck(:id).reverse
    patch reorder_settings_card_statuses_path, params: { order: ids }
    assert_response :success
    assert_equal ids, CardStatus.ordered.pluck(:id)
  end
end
```

> fixture `card_statuses(:vip)`, `card_statuses(:hold)`가 없으면 `test/fixtures/card_statuses.yml`에 추가.

- [ ] **Step 7.3: 컨트롤러 작성**

Create `app/controllers/settings/card_statuses_controller.rb`:
```ruby
# frozen_string_literal: true

module Settings
  class CardStatusesController < BaseController
    before_action :set_card_status, only: %i[update destroy inline_rename]

    def index
      @card_statuses = CardStatus.ordered
      @color_presets = CardStatusColorPresets::ALL
      @card_status ||= CardStatus.new
    end

    def create
      @card_status = CardStatus.new(card_status_params)
      if @card_status.save
        redirect_to settings_card_statuses_path, notice: "상태가 추가되었습니다."
      else
        @card_statuses = CardStatus.ordered
        @color_presets = CardStatusColorPresets::ALL
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @card_status.update(card_status_params)
        redirect_to settings_card_statuses_path, notice: "상태가 수정되었습니다."
      else
        @card_statuses = CardStatus.ordered
        @color_presets = CardStatusColorPresets::ALL
        render :index, status: :unprocessable_entity
      end
    end

    # 인라인 rename 전용 — name 하나만 수정
    def inline_rename
      if @card_status.update(name: params[:name])
        render json: { status: "ok", name: @card_status.name }
      else
        render json: { status: "error", errors: @card_status.errors.full_messages },
               status: :unprocessable_entity
      end
    end

    def destroy
      CardStatus.transaction do
        @card_status.lock!
        if @card_status.deletable?
          @card_status.destroy!
          redirect_to settings_card_statuses_path, notice: "상태가 삭제되었습니다."
        else
          reason = @card_status.is_system? ? "시스템 내장 상태는 삭제할 수 없습니다." : "이 상태를 사용 중인 카드 #{@card_status.orders.count}건이 있습니다."
          redirect_to settings_card_statuses_path, alert: reason, status: :see_other
        end
      end
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to settings_card_statuses_path, alert: "삭제 실패."
    end

    def reorder
      ids = Array(params[:order]).map(&:to_i)
      CardStatus.transaction do
        ids.each_with_index do |id, idx|
          CardStatus.where(id: id).update_all(position: idx + 1)
        end
      end
      render json: { status: "ok" }
    end

    private

    def set_card_status
      @card_status = CardStatus.find(params[:id])
    end

    def card_status_params
      params.require(:card_status).permit(
        :key, :name, :bg_color, :border_color, :text_color,
        :is_default, :auto_priority, :auto_rule
      ).tap do |p|
        # is_system 은 API로 변경 불가 (seed에서만 설정)
        # is_default 변경 시 기존 default는 false로 리셋
        if p[:is_default] == "1" || p[:is_default] == true
          CardStatus.where(is_default: true).where.not(id: params[:id]).update_all(is_default: false)
        end
      end
    end
  end
end
```

- [ ] **Step 7.4: Settings 사이드바에 링크 추가**

Modify `app/views/settings/base/index.html.erb` — 기존 "메뉴 권한" 링크 근처에 새 카드 추가:
```erb
<div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-4">
  <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-2">칸반 상태 관리</h3>
  <p class="text-xs text-gray-500 dark:text-gray-500 mb-3">카드 상태 이름·색상·자동 배정 규칙을 편집합니다.</p>
  <%= link_to settings_card_statuses_path, class: "text-sm text-primary dark:text-accent hover:underline" do %>
    관리하러 가기 →
  <% end %>
</div>
```

- [ ] **Step 7.5: 테스트 실행**

Run: `bin/rails test test/controllers/settings/card_statuses_controller_test.rb`
Expected: 모두 pass

- [ ] **Step 7.6: 커밋**

```bash
git add config/routes.rb \
        app/controllers/settings/card_statuses_controller.rb \
        app/views/settings/base/index.html.erb \
        test/controllers/settings/card_statuses_controller_test.rb
git commit -m "feat(card-status): Settings CRUD + reorder + inline_rename 컨트롤러"
```

---

## Task 8: Settings UI (index + edit modal + Stimulus)

**Files:**
- Create: `app/views/settings/card_statuses/index.html.erb`
- Create: `app/views/settings/card_statuses/_row.html.erb`
- Create: `app/views/settings/card_statuses/_edit_modal.html.erb`
- Create: `app/javascript/controllers/card_status_preview_controller.js`
- Create: `app/javascript/controllers/card_status_sortable_controller.js`

- [ ] **Step 8.1: 리스트 뷰 작성**

Create `app/views/settings/card_statuses/index.html.erb`:
```erb
<% content_for :title, "칸반 상태 관리" %>

<div class="max-w-4xl mx-auto p-6">
  <div class="flex items-center justify-between mb-5">
    <h1 class="text-xl font-bold text-gray-900 dark:text-white">칸반 상태 관리</h1>
    <button type="button" onclick="openCardStatusModal()"
            class="px-3 py-2 bg-[#00A1E0] text-white rounded-lg text-sm font-medium hover:bg-[#0083b7]">
      + 새 상태 추가
    </button>
  </div>

  <% flash.each do |type, msg| %>
    <div class="mb-3 px-3 py-2 rounded text-sm <%= type == 'notice' ? 'bg-green-50 text-green-800' : 'bg-red-50 text-red-800' %>"><%= msg %></div>
  <% end %>

  <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700"
       data-controller="card-status-sortable"
       data-card-status-sortable-url-value="<%= reorder_settings_card_statuses_path %>">
    <% @card_statuses.each do |cs| %>
      <%= render "row", cs: cs %>
    <% end %>
  </div>

  <p class="mt-4 text-xs text-gray-500">
    💡 '시스템' 상태는 라벨·색상은 수정 가능, 삭제는 불가합니다. 삭제는 해당 상태를 쓰는 카드가 0건일 때만 가능합니다.
  </p>
</div>

<%= render "edit_modal", card_status: @card_status || CardStatus.new, color_presets: @color_presets %>

<script>
  function openCardStatusModal(id) {
    const modal = document.getElementById('card-status-modal');
    modal.classList.remove('hidden');
    if (id) {
      modal.dataset.editingId = id;
      // 실제 값 로드는 간단히 하려고 별도 edit 페이지 대신 data-* 속성에서 읽어옴
      const row = document.querySelector(`[data-card-status-row="${id}"]`);
      if (row) {
        document.getElementById('cs-name').value = row.dataset.name;
        document.getElementById('cs-bg').value   = row.dataset.bg;
        document.getElementById('cs-border').value = row.dataset.border;
        document.getElementById('cs-text').value = row.dataset.text;
      }
    } else {
      modal.dataset.editingId = '';
      document.getElementById('card-status-form').reset();
    }
  }
  function closeCardStatusModal() {
    document.getElementById('card-status-modal').classList.add('hidden');
  }
  function inlineRename(id, newName) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    fetch(`/settings/card_statuses/${id}/inline_rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
      body: JSON.stringify({ name: newName })
    }).then(r => r.json()).then(d => {
      if (d.status !== 'ok') alert(d.errors?.join(', ') || '저장 실패');
    });
  }
</script>
```

- [ ] **Step 8.2: Row partial 작성**

Create `app/views/settings/card_statuses/_row.html.erb`:
```erb
<div class="flex items-center gap-3 px-4 py-3 border-b border-gray-200 dark:border-gray-700 last:border-0"
     data-card-status-row="<%= cs.id %>"
     data-cs-id="<%= cs.id %>"
     data-name="<%= cs.name %>"
     data-bg="<%= cs.bg_color %>"
     data-border="<%= cs.border_color %>"
     data-text="<%= cs.text_color %>">

  <span class="cursor-move text-gray-400 hover:text-gray-600" data-sortable-handle>≡</span>

  <span class="inline-block w-6 h-6 rounded" style="background:<%= cs.bg_color %>; border:1px solid <%= cs.border_color %>"></span>

  <span class="flex-1 text-sm font-medium"
        contenteditable="true"
        ondblclick="this.focus()"
        onblur="inlineRename(<%= cs.id %>, this.textContent.trim())"><%= cs.name %></span>

  <% if cs.is_system? %>
    <span class="text-xs text-gray-400">시스템</span>
  <% elsif cs.orders.count > 0 %>
    <span class="text-xs text-gray-400">사용 <%= cs.orders.count %>건</span>
  <% end %>

  <% if cs.is_default? %>
    <span class="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded">기본값</span>
  <% end %>

  <span class="text-xs text-gray-500">
    <% if (r = cs.parsed_auto_rule) %>
      자동: <%= r["when"] == "due_date" ? "마감 #{r["value"]}일 #{r["operator"] == "lte" ? "이내" : "이상"}" : r["when"] %>
    <% else %>
      수동
    <% end %>
  </span>

  <button type="button" onclick="openCardStatusModal(<%= cs.id %>)"
          class="text-xs text-blue-600 hover:underline">편집</button>

  <% unless cs.is_system? %>
    <%= button_to "삭제",
                  settings_card_status_path(cs),
                  method: :delete,
                  data: { confirm: "정말 삭제하시겠습니까?" },
                  form_class: "inline",
                  class: "text-xs text-red-600 hover:underline bg-transparent border-0 cursor-pointer p-0 disabled:opacity-30 disabled:cursor-not-allowed",
                  disabled: cs.orders.count.positive?,
                  title: (cs.orders.count.positive? ? "사용 중인 카드 #{cs.orders.count}건 있음" : "삭제") %>
  <% end %>
</div>
```

- [ ] **Step 8.3: Edit modal 작성**

Create `app/views/settings/card_statuses/_edit_modal.html.erb`:
```erb
<div id="card-status-modal" class="hidden fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4"
     data-controller="card-status-preview">

  <%= form_with model: card_status, url: (card_status.persisted? ? settings_card_status_path(card_status) : settings_card_statuses_path),
                method: (card_status.persisted? ? :patch : :post),
                id: "card-status-form",
                class: "bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-lg p-6" do |f| %>

    <h2 class="text-lg font-bold mb-4">상태 편집</h2>

    <div class="space-y-3">
      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-1.5">라벨 이름</label>
        <%= f.text_field :name, id: "cs-name",
                         data: { action: "input->card-status-preview#refresh", card_status_preview_target: "name" },
                         class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm text-gray-900 bg-white" %>
      </div>

      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-1.5">색상 프리셋</label>
        <div class="grid grid-cols-6 gap-2">
          <% color_presets.each do |preset| %>
            <button type="button" title="<%= preset[:name] %>"
                    class="w-full h-8 rounded border border-gray-300"
                    style="background:<%= preset[:bg] %>"
                    data-action="click->card-status-preview#applyPreset"
                    data-bg="<%= preset[:bg] %>"
                    data-border="<%= preset[:border] %>"
                    data-text="<%= preset[:text] %>">
            </button>
          <% end %>
        </div>
      </div>

      <details class="text-xs">
        <summary class="cursor-pointer text-gray-600">▼ 커스텀 색상 직접 지정</summary>
        <div class="grid grid-cols-3 gap-3 mt-2">
          <div>
            <label class="block text-xs text-gray-600 mb-1">배경</label>
            <%= f.color_field :bg_color, id: "cs-bg",
                              data: { action: "input->card-status-preview#refresh", card_status_preview_target: "bg" },
                              class: "w-full h-10" %>
          </div>
          <div>
            <label class="block text-xs text-gray-600 mb-1">보더</label>
            <%= f.color_field :border_color, id: "cs-border",
                              data: { action: "input->card-status-preview#refresh", card_status_preview_target: "border" },
                              class: "w-full h-10" %>
          </div>
          <div>
            <label class="block text-xs text-gray-600 mb-1">글자</label>
            <%= f.color_field :text_color, id: "cs-text",
                              data: { action: "input->card-status-preview#refresh", card_status_preview_target: "text" },
                              class: "w-full h-10" %>
          </div>
        </div>
      </details>

      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-1.5">미리보기</label>
        <div data-card-status-preview-target="card"
             class="rounded-lg border p-3 shadow-sm text-sm"
             style="background:<%= card_status.bg_color.presence || '#FAFAFA' %>; border-color:<%= card_status.border_color.presence || '#E5E7EB' %>; color:<%= card_status.text_color.presence || '#374151' %>">
          <div data-card-status-preview-target="cardName" class="font-semibold mb-1"><%= card_status.name.presence || "샘플 상태" %></div>
          <div>Nawah PO 4500019288</div>
          <div class="text-xs opacity-75">2026-04-20 마감</div>
        </div>
      </div>

      <details class="text-xs">
        <summary class="cursor-pointer text-gray-600">자동 배정 규칙</summary>
        <div class="mt-2 space-y-2">
          <label class="flex items-center gap-2"><input type="radio" name="card_status[auto_mode]" value="manual" checked> 수동 전용</label>
          <label class="flex items-center gap-2"><input type="radio" name="card_status[auto_mode]" value="lte_days"> 마감
            <input type="number" name="card_status[auto_days]" min="0" max="90" class="w-16 px-2 py-1 border border-gray-300 rounded">
            일 이내
          </label>
          <label class="flex items-center gap-2"><input type="radio" name="card_status[auto_mode]" value="overdue"> 마감 경과 시</label>

          <label class="block mt-2">우선순위: <input type="number" name="card_status[auto_priority]" value="<%= card_status.auto_priority || 0 %>" class="w-20 px-2 py-1 border border-gray-300 rounded"></label>
        </div>
      </details>
    </div>

    <div class="flex justify-end gap-2 mt-5">
      <button type="button" onclick="closeCardStatusModal()" class="px-4 py-2 text-sm border border-gray-300 rounded-lg">취소</button>
      <%= f.submit "저장", class: "px-4 py-2 bg-[#00A1E0] text-white text-sm rounded-lg" %>
    </div>

    <%# auto_rule JSON 직렬화 — 폼 제출 시 라디오 값 → JSON 문자열 %>
    <%= hidden_field_tag "card_status[auto_rule]", "", id: "cs-auto-rule-hidden" %>
    <script>
      document.getElementById("card-status-form")?.addEventListener("submit", function() {
        const mode = document.querySelector('input[name="card_status[auto_mode]"]:checked')?.value;
        const days = document.querySelector('input[name="card_status[auto_days]"]')?.value;
        let rule = "";
        if (mode === "lte_days" && days) {
          rule = JSON.stringify({ when: "due_date", operator: "lte", value: parseInt(days, 10) });
        } else if (mode === "overdue") {
          rule = JSON.stringify({ when: "due_date", operator: "lte", value: 0 });
        }
        document.getElementById("cs-auto-rule-hidden").value = rule;
      });
    </script>
  <% end %>
</div>
```

- [ ] **Step 8.4: Stimulus 미리보기 컨트롤러**

Create `app/javascript/controllers/card_status_preview_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "bg", "border", "text", "card", "cardName"]

  refresh() {
    if (this.hasCardTarget) {
      if (this.hasBgTarget)     this.cardTarget.style.background  = this.bgTarget.value
      if (this.hasBorderTarget) this.cardTarget.style.borderColor = this.borderTarget.value
      if (this.hasTextTarget)   this.cardTarget.style.color       = this.textTarget.value
    }
    if (this.hasCardNameTarget && this.hasNameTarget) {
      this.cardNameTarget.textContent = this.nameTarget.value || "샘플 상태"
    }
  }

  applyPreset(event) {
    const btn = event.currentTarget
    this.bgTarget.value     = btn.dataset.bg
    this.borderTarget.value = btn.dataset.border
    this.textTarget.value   = btn.dataset.text
    this.refresh()
  }
}
```

- [ ] **Step 8.5: Sortable 컨트롤러 (Sortable.js CDN 활용)**

Create `app/javascript/controllers/card_status_sortable_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!window.Sortable) {
      // CDN 로드 (이미 있으면 스킵)
      const script = document.createElement("script")
      script.src = "https://cdn.jsdelivr.net/npm/sortablejs@1.15.0/Sortable.min.js"
      script.onload = () => this.initSortable()
      document.head.appendChild(script)
    } else {
      this.initSortable()
    }
  }

  initSortable() {
    Sortable.create(this.element, {
      handle: "[data-sortable-handle]",
      animation: 150,
      onEnd: () => this.persist()
    })
  }

  async persist() {
    const ids = Array.from(this.element.querySelectorAll("[data-cs-id]"))
                    .map(el => parseInt(el.dataset.csId, 10))
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ order: ids })
    })
  }
}
```

- [ ] **Step 8.6: 컨트롤러 등록 확인**

Run: `cat app/javascript/controllers/index.js`

Ensure Stimulus auto-import registers the two new controllers. If the codebase uses `application.register` explicitly, append:
```javascript
import CardStatusPreviewController from "./card_status_preview_controller"
import CardStatusSortableController from "./card_status_sortable_controller"
application.register("card-status-preview",  CardStatusPreviewController)
application.register("card-status-sortable", CardStatusSortableController)
```

- [ ] **Step 8.7: 서버 확인**

Run: `bin/rails server -p 3001 -d && sleep 3 && curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:3001/settings/card_statuses; kill $(lsof -ti:3001)`
Expected: 302 (로그인 필요)

- [ ] **Step 8.8: 커밋**

```bash
git add app/views/settings/card_statuses/ \
        app/javascript/controllers/card_status_preview_controller.js \
        app/javascript/controllers/card_status_sortable_controller.js \
        app/javascript/controllers/index.js
git commit -m "feat(card-status): Settings UI — 리스트·인라인 rename·편집 모달·드래그 정렬"
```

---

## Task 9: System 테스트 + 일간 배치 Job

**Files:**
- Create: `test/system/card_status_management_test.rb`
- Create: `app/jobs/card_status_auto_assign_job.rb`
- Modify: `config/recurring.yml` (SolidQueue 크론)

- [ ] **Step 9.1: System 테스트**

Create `test/system/card_status_management_test.rb`:
```ruby
require "application_system_test_case"

class CardStatusManagementTest < ApplicationSystemTestCase
  setup { login_as users(:one) }  # helper — 프로젝트 devise 설정 따라

  test "rename via inline edit" do
    visit settings_card_statuses_path
    row = find("[data-cs-id=\"#{card_statuses(:vip).id}\"]")
    within(row) do
      name_el = find("[contenteditable=true]")
      name_el.click
      name_el.send_keys [:control, "a"], :backspace, "VVVIP"
      name_el.send_keys :tab  # blur
    end
    sleep 0.5
    assert_equal "VVVIP", card_statuses(:vip).reload.name
  end

  test "delete blocks when in use" do
    cs = card_statuses(:vip)
    Order.create!(title: "X", customer_name: "A", status: "new_rfq", card_status: cs)

    visit settings_card_statuses_path
    row = find("[data-cs-id=\"#{cs.id}\"]")
    within(row) do
      delete_btn = find("button[title*='사용 중']")
      assert delete_btn.disabled?
    end
  end
end
```

- [ ] **Step 9.2: 일간 배치 Job**

Create `app/jobs/card_status_auto_assign_job.rb`:
```ruby
# frozen_string_literal: true

# 매일 새벽 — due_date 변경·마감 임박·경과된 Order들의 card_status 재평가
class CardStatusAutoAssignJob < ApplicationJob
  queue_as :default

  def perform
    Order.where(card_status_manually_set_at: nil)
         .where.not(status: %i[get_grn give_up done])
         .find_each(batch_size: 200) do |order|
      target = CardStatus::AutoAssigner.call(order)
      next if order.card_status_id == target.id
      order.update_column(:card_status_id, target.id)
    end
  end
end
```

- [ ] **Step 9.3: 크론 등록**

Modify `config/recurring.yml` — 파일 없으면 생성:
```yaml
production:
  card_status_reassess:
    class: CardStatusAutoAssignJob
    schedule: every day at 17:00 UTC   # UAE 21:00 / KST 02:00
    queue: default
```

- [ ] **Step 9.4: 테스트 실행**

Run: `bin/rails test:system test/system/card_status_management_test.rb`
Expected: 2 tests pass (Chrome/Chromium 필요)

- [ ] **Step 9.5: 커밋**

```bash
git add test/system/card_status_management_test.rb \
        app/jobs/card_status_auto_assign_job.rb \
        config/recurring.yml
git commit -m "feat(card-status): 일간 배치 Job + System 테스트"
```

---

## Task 10: priority 컬럼 제거 + 최종 회귀

**Files:**
- Create: `db/migrate/20260414120004_drop_orders_priority.rb`
- Modify: `test/fixtures/orders.yml` (priority: 라인 제거)

- [ ] **Step 10.1: 전체 회귀 테스트 (priority 제거 전 최종 확인)**

Run: `bin/rails test`
Expected: 모두 pass.

- [ ] **Step 10.2: `priority` 컬럼 drop 마이그레이션**

Create `db/migrate/20260414120004_drop_orders_priority.rb`:
```ruby
class DropOrdersPriority < ActiveRecord::Migration[8.1]
  def up
    remove_column :orders, :priority
  end

  def down
    add_column :orders, :priority, :integer, default: 1
  end
end
```

- [ ] **Step 10.3: fixture에서 priority 제거**

Modify `test/fixtures/orders.yml` — 모든 엔트리의 `priority:` 줄 제거.
Run: `grep -n "priority:" test/fixtures/orders.yml` → 0건이어야 함.

- [ ] **Step 10.4: 마이그레이션 + 최종 회귀**

Run:
```
bin/rails db:migrate
bin/rails test
```
Expected: 모두 pass.

- [ ] **Step 10.5: 코드 전체 grep으로 priority 잔재 확인**

Run:
```
grep -rn "priority" app/ --include="*.rb" --include="*.erb" | grep -v "card_status\|CardStatus::AutoAssigner\|PriorityColors\|auto_priority" | head
```
Expected: 0건 (또는 주석에만 존재).

잔재가 있으면 수정 후 재커밋.

- [ ] **Step 10.6: 커밋**

```bash
git add db/migrate/20260414120004_drop_orders_priority.rb \
        test/fixtures/orders.yml
git commit -m "feat(card-status): orders.priority 컬럼 제거 — CardStatus 전환 완료"
```

---

## Task 11: 프로덕션 배포

**Files:** 없음 (배포 명령)

- [ ] **Step 11.1: 최종 회귀 + RuboCop**

Run:
```
bin/rails test
bundle exec rubocop app/models/card_status.rb app/controllers/settings/card_statuses_controller.rb app/services/card_status/auto_assigner.rb app/jobs/card_status_auto_assign_job.rb
```

- [ ] **Step 11.2: push + 배포**

Run:
```
git push
kamal deploy
```

Expected: deploy 성공.

- [ ] **Step 11.3: 프로덕션 마이그레이션 + seed**

Run:
```
kamal app exec --reuse "bin/rails db:migrate"
kamal app exec --reuse "bin/rails db:seed"
```

- [ ] **Step 11.4: 프로덕션 실측**

```
kamal app exec --reuse "bin/rails runner 'puts CardStatus.count; puts Order.joins(:card_status).count'"
```
Expected: CardStatus=7, Order join 수 == Order.count

- [ ] **Step 11.5: 브라우저 확인**

대표님 확인: `https://cpoflow.ddtl.co.kr/settings/card_statuses`에서 7개 프리셋 표시되는지, 이름 더블클릭 편집 동작, 칸반 페이지 카드 색상 정상인지.

- [ ] **Step 11.6: 최종 커밋 없음** (배포 자체는 코드 변경 없음)

---

## Execution Notes

- 각 Task는 **독립 배포 가능**하도록 설계됨. Task 4까지는 `priority` 컬럼이 살아있어 이전 코드도 동작함.
- Task 5~6에서 뷰·Gmail 파이프라인이 `card_status` 기반으로 전환됨.
- Task 10에서 비로소 `priority` 컬럼이 사라짐. 이전 Task 완료 후 회귀 통과 여부를 매번 확인.
- 프로덕션 seed는 로컬 개발 seed와 동일 (`db/seeds/card_statuses.rb`). 대표님 UAE 서버에서 `kamal app exec --reuse "bin/rails db:seed"` 실행 시점 이전에는 정상 동작 불가.
