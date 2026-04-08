# Procurement Ontology M1 — Skeleton & Auto Links

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `order_links` polymorphic 테이블과 `OrderLink` 모델, `GraphNode` concern, 자동 링크 콜백 4종, 데이터 백필 rake task를 구축한다. UI는 Drawer Detail 탭에 임시 텍스트 리스트로만 표시한다 (M2에서 시각화).

**Architecture:** 단일 polymorphic 조인 테이블(`source`/`target`)에 5종 relation을 저장. `GraphNode` concern을 `Order`/`OrderQuote`에 include하여 양방향 traversal API 노출. 시스템 이벤트(after_create_commit, status 전환) 콜백으로 confirmed 상태 링크 자동 생성. 백필 rake task는 dry-run 우선, 멱등 처리.

**Tech Stack:** Rails 8.1 / SQLite3 / Minitest / ActiveRecord polymorphic / `serialize :metadata, coder: JSON`

**Spec:** `docs/superpowers/specs/2026-04-08-procurement-ontology-design.md` (섹션 4, 6.M1)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `db/migrate/20260408120000_create_order_links.rb` | Create | `order_links` 테이블 + 4 인덱스 |
| `app/models/order_link.rb` | Create | `OrderLink` 모델 — polymorphic, validation, scopes |
| `app/models/concerns/graph_node.rb` | Create | `outgoing_links`/`incoming_links`/`linked_nodes` API |
| `app/models/order.rb` | Modify | `include GraphNode` + 콜백 3종 (status 전환 2, parent_order 변경 1) |
| `app/models/order_quote.rb` | Modify | `include GraphNode` + 콜백 1종 (`after_create_commit → quoted_as`) |
| `lib/tasks/order_links.rake` | Create | `order_links:backfill` + `order_links:backfill:dry_run` |
| `app/views/orders/_drawer_links.html.erb` | Create | Drawer Detail 탭에 임시 텍스트 리스트 partial |
| `app/views/orders/_drawer.html.erb` (또는 detail partial) | Modify | `_drawer_links` partial 렌더링 추가 |
| `test/models/order_link_test.rb` | Create | OrderLink validation/scope 5케이스 |
| `test/models/concerns/graph_node_test.rb` | Create | concern API 3케이스 |
| `test/models/order_quote_test.rb` | Modify | `quoted_as` 자동 생성 1케이스 |
| `test/models/order_test.rb` | Modify | `confirmed_to`, `delivered_as`, `derived_from` 3케이스 |

---

## Task 1 — 마이그레이션 + 모델 골격 (실패 테스트 우선)

**Files:**
- Create: `db/migrate/20260408120000_create_order_links.rb`
- Create: `app/models/order_link.rb`
- Test: `test/models/order_link_test.rb`

- [ ] **Step 1.1: 실패 테스트 작성 — `order_link_test.rb`**

```ruby
# test/models/order_link_test.rb
require "test_helper"

class OrderLinkTest < ActiveSupport::TestCase
  setup do
    @user     = User.first || User.create!(email: "test@example.com", password: "password123", name: "Test")
    @order_a  = Order.create!(user: @user, title: "RFQ A", reference_no: "TEST-001", status: :new_rfq)
    @order_b  = Order.create!(user: @user, title: "PO B",  reference_no: "TEST-001", status: :new_po)
  end

  test "polymorphic source/target 양쪽 set 시 valid" do
    link = OrderLink.new(
      source: @order_a, target: @order_b,
      relation: "derived_from", status: "confirmed", confidence: 1.0
    )
    assert link.valid?, link.errors.full_messages.join(", ")
  end

  test "relation 화이트리스트 미포함 시 invalid" do
    link = OrderLink.new(source: @order_a, target: @order_b, relation: "bogus")
    assert_not link.valid?
    assert_includes link.errors[:relation], "is not included in the list"
  end

  test "status 화이트리스트 미포함 시 invalid" do
    link = OrderLink.new(source: @order_a, target: @order_b, relation: "references", status: "bogus")
    assert_not link.valid?
  end

  test "confidence 0.0~1.0 범위 강제" do
    link = OrderLink.new(source: @order_a, target: @order_b, relation: "references", confidence: 1.5)
    assert_not link.valid?
  end

  test "metadata JSON serialize/deserialize" do
    link = OrderLink.create!(
      source: @order_a, target: @order_b, relation: "references",
      metadata: { source: "manual", note: "테스트" }
    )
    link.reload
    assert_equal "manual", link.metadata["source"]
    assert_equal "테스트", link.metadata["note"]
  end

  test "for_node scope — source 또는 target 매칭" do
    OrderLink.create!(source: @order_a, target: @order_b, relation: "references")
    assert_equal 1, OrderLink.for_node(@order_a).count
    assert_equal 1, OrderLink.for_node(@order_b).count
  end
end
```

- [ ] **Step 1.2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/order_link_test.rb -v`

Expected: ALL FAIL with `NameError: uninitialized constant OrderLinkTest::OrderLink` 또는 테이블 없음 오류

- [ ] **Step 1.3: 마이그레이션 작성**

```ruby
# db/migrate/20260408120000_create_order_links.rb
class CreateOrderLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :order_links do |t|
      t.references :source, polymorphic: true, null: false
      t.references :target, polymorphic: true, null: false
      t.string  :relation, null: false
      t.text    :metadata
      t.string  :status, null: false, default: "confirmed"
      t.float   :confidence, null: false, default: 1.0
      t.references :created_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end

    add_index :order_links, [:source_type, :source_id], name: "idx_order_links_source"
    add_index :order_links, [:target_type, :target_id], name: "idx_order_links_target"
    add_index :order_links, [:relation, :status], name: "idx_order_links_rel_status"
    add_index :order_links,
              [:source_type, :source_id, :target_type, :target_id, :relation],
              unique: true, name: "idx_order_links_unique"
  end
end
```

- [ ] **Step 1.4: 마이그레이션 실행**

Run: `bin/rails db:migrate`

Expected: `== 20260408120000 CreateOrderLinks: migrated` 출력

- [ ] **Step 1.5: 모델 작성**

```ruby
# app/models/order_link.rb
class OrderLink < ApplicationRecord
  RELATIONS = %w[derived_from quoted_as confirmed_to delivered_as references].freeze
  STATUSES  = %w[confirmed suggested rejected].freeze

  belongs_to :source, polymorphic: true
  belongs_to :target, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  serialize :metadata, coder: JSON

  validates :relation,   inclusion: { in: RELATIONS }
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, numericality: { in: 0.0..1.0 }

  scope :confirmed, -> { where(status: "confirmed") }
  scope :suggested, -> { where(status: "suggested") }
  scope :rejected,  -> { where(status: "rejected") }
  scope :for_node, ->(node) {
    where(source_type: node.class.name, source_id: node.id)
      .or(where(target_type: node.class.name, target_id: node.id))
  }
end
```

- [ ] **Step 1.6: 테스트 재실행 — 통과 확인**

Run: `bin/rails test test/models/order_link_test.rb -v`

Expected: `6 runs, ... 0 failures, 0 errors`

- [ ] **Step 1.7: 커밋**

```bash
git add db/migrate/20260408120000_create_order_links.rb \
        app/models/order_link.rb \
        test/models/order_link_test.rb \
        db/schema.rb
git commit -m "feat(ontology): order_links 테이블 + OrderLink 모델 (M1-1)

polymorphic source/target + 5종 relation + JSON metadata.
6 케이스 테스트 통과."
```

---

## Task 2 — `GraphNode` Concern + `Order`/`OrderQuote` include

**Files:**
- Create: `app/models/concerns/graph_node.rb`
- Modify: `app/models/order.rb` (`include GraphNode` 1줄 추가)
- Modify: `app/models/order_quote.rb` (`include GraphNode` 1줄 추가)
- Test: `test/models/concerns/graph_node_test.rb`

- [ ] **Step 2.1: 실패 테스트 작성**

```ruby
# test/models/concerns/graph_node_test.rb
require "test_helper"

class GraphNodeTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "g@example.com", password: "password123", name: "G")
    @rfq  = Order.create!(user: @user, title: "RFQ", reference_no: "GN-001", status: :new_rfq)
    @po   = Order.create!(user: @user, title: "PO",  reference_no: "GN-001", status: :new_po)
    OrderLink.create!(source: @rfq, target: @po, relation: "confirmed_to", status: "confirmed")
  end

  test "outgoing_links 반환" do
    assert_equal 1, @rfq.outgoing_links.count
    assert_equal "confirmed_to", @rfq.outgoing_links.first.relation
  end

  test "incoming_links 반환" do
    assert_equal 1, @po.incoming_links.count
  end

  test "linked_nodes 양방향 합산 + 중복 제거" do
    nodes_from_rfq = @rfq.linked_nodes
    nodes_from_po  = @po.linked_nodes
    assert_includes nodes_from_rfq, @po
    assert_includes nodes_from_po, @rfq
  end
end
```

- [ ] **Step 2.2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/concerns/graph_node_test.rb -v`

Expected: FAIL with `NoMethodError: undefined method 'outgoing_links' for #<Order ...>`

- [ ] **Step 2.3: Concern 작성**

```ruby
# app/models/concerns/graph_node.rb
module GraphNode
  extend ActiveSupport::Concern

  included do
    has_many :outgoing_links,
             as: :source,
             class_name: "OrderLink",
             dependent: :destroy
    has_many :incoming_links,
             as: :target,
             class_name: "OrderLink",
             dependent: :destroy
  end

  # 양방향 연결된 노드 반환 (source/target 합산, 중복 제거)
  def linked_nodes(relation: nil, status: "confirmed")
    out = outgoing_links.where(status: status)
    inc = incoming_links.where(status: status)
    if relation
      out = out.where(relation: relation)
      inc = inc.where(relation: relation)
    end
    (out.map(&:target) + inc.map(&:source)).uniq
  end
end
```

- [ ] **Step 2.4: `Order` 모델에 include 추가**

`app/models/order.rb` 클래스 최상단(현재 `belongs_to :user` 윗줄)에 추가:

```ruby
class Order < ApplicationRecord
  include GraphNode

  belongs_to :user     # creator
  # ... 기존 코드 그대로
```

- [ ] **Step 2.5: `OrderQuote` 모델에 include 추가**

`app/models/order_quote.rb` 클래스 최상단에 추가:

```ruby
class OrderQuote < ApplicationRecord
  include GraphNode

  # ... 기존 코드 그대로
```

- [ ] **Step 2.6: 테스트 재실행 — 통과 확인**

Run: `bin/rails test test/models/concerns/graph_node_test.rb test/models/order_link_test.rb -v`

Expected: `9 runs, 0 failures, 0 errors`

- [ ] **Step 2.7: 회귀 테스트 — 기존 Order/OrderQuote 테스트 통과 확인**

Run: `bin/rails test test/models/order_test.rb test/models/order_quote_test.rb -v`

Expected: 0 failures, 0 errors (concern 추가가 기존 동작에 영향 없음)

- [ ] **Step 2.8: 커밋**

```bash
git add app/models/concerns/graph_node.rb \
        app/models/order.rb \
        app/models/order_quote.rb \
        test/models/concerns/graph_node_test.rb
git commit -m "feat(ontology): GraphNode concern + Order/OrderQuote include (M1-2)

outgoing_links/incoming_links/linked_nodes API.
3 케이스 + 회귀 0건."
```

---

## Task 3 — 자동 콜백: `OrderQuote.after_create → quoted_as`

**Files:**
- Modify: `app/models/order_quote.rb`
- Test: `test/models/order_quote_test.rb` (수정 또는 신설)

- [ ] **Step 3.1: 실패 테스트 작성 (또는 추가)**

`test/models/order_quote_test.rb`가 없으면 신설, 있으면 아래 케이스 추가:

```ruby
# test/models/order_quote_test.rb
require "test_helper"

class OrderQuoteTest < ActiveSupport::TestCase
  test "after_create_commit → quoted_as 링크 자동 생성" do
    user  = User.first || User.create!(email: "q@example.com", password: "password123", name: "Q")
    order = Order.create!(user: user, title: "RFQ", reference_no: "QA-001", status: :new_rfq)

    assert_difference "OrderLink.count", 1 do
      OrderQuote.create!(order: order, supplier_name: "Test Supplier", total_amount: 1000)
    end

    link = OrderLink.last
    assert_equal "quoted_as", link.relation
    assert_equal "confirmed", link.status
    assert_equal order, link.source
    assert_equal "system_event", link.metadata["source"]
    assert_equal "OrderQuote.after_create", link.metadata["trigger"]
  end
end
```

> 주의: `OrderQuote` 의 실제 필수 필드(`supplier_name`, `total_amount` 등)는 `app/models/order_quote.rb`를 먼저 읽어 정확한 이름으로 교체할 것. 컬럼이 다르면 schema에 맞춰 보정.

- [ ] **Step 3.2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/order_quote_test.rb -v`

Expected: FAIL with `expected #count to have changed by 1, but was changed by 0`

- [ ] **Step 3.3: 콜백 추가**

`app/models/order_quote.rb` — `include GraphNode` 아래, 기존 association 위 또는 아래에 추가:

```ruby
class OrderQuote < ApplicationRecord
  include GraphNode

  # ... 기존 belongs_to/validates 등

  after_create_commit :create_quoted_link

  private

  def create_quoted_link
    OrderLink.find_or_create_by!(
      source_type: "Order",
      source_id:   order_id,
      target_type: "OrderQuote",
      target_id:   id,
      relation:    "quoted_as"
    ) do |link|
      link.status     = "confirmed"
      link.confidence = 1.0
      link.metadata   = { source: "system_event", trigger: "OrderQuote.after_create" }
    end
  end
end
```

- [ ] **Step 3.4: 테스트 재실행 — 통과 확인**

Run: `bin/rails test test/models/order_quote_test.rb -v`

Expected: 1 run, 0 failures

- [ ] **Step 3.5: 멱등성 수동 검증**

Run: `bin/rails runner 'q = OrderQuote.last; q.send(:create_quoted_link); puts OrderLink.where(target: q, relation: "quoted_as").count'`

Expected: `1` (중복 생성 안 됨)

- [ ] **Step 3.6: 커밋**

```bash
git add app/models/order_quote.rb test/models/order_quote_test.rb
git commit -m "feat(ontology): OrderQuote.after_create_commit → quoted_as 자동 링크 (M1-3)

find_or_create_by 멱등성. metadata에 source/trigger 기록."
```

---

## Task 4 — 자동 콜백: `Order` 상태 전환 → `confirmed_to` / `delivered_as`

**Files:**
- Modify: `app/models/order.rb`
- Modify: `test/models/order_test.rb`

- [ ] **Step 4.1: 실패 테스트 작성**

`test/models/order_test.rb` 끝에 추가:

```ruby
  test "status: pending_po → new_po + parent 있으면 confirmed_to 자동 생성" do
    user   = User.first || User.create!(email: "c@example.com", password: "password123", name: "C")
    parent = Order.create!(user: user, title: "RFQ", reference_no: "CT-001", status: :pending_po)
    child  = Order.create!(user: user, title: "PO",  reference_no: "CT-001", status: :pending_po, parent_order: parent)

    assert_difference "OrderLink.where(relation: 'confirmed_to').count", 1 do
      child.update!(status: :new_po)
    end

    link = OrderLink.where(relation: "confirmed_to").last
    assert_equal parent, link.source
    assert_equal child,  link.target
    assert_equal "system_event", link.metadata["source"]
  end

  test "status: → get_grn + parent 있으면 delivered_as 자동 생성" do
    user   = User.first || User.create!(email: "d@example.com", password: "password123", name: "D")
    parent = Order.create!(user: user, title: "PO",  reference_no: "DA-001", status: :delivery_items)
    child  = Order.create!(user: user, title: "GRN", reference_no: "DA-001", status: :delivery_items, parent_order: parent)

    assert_difference "OrderLink.where(relation: 'delivered_as').count", 1 do
      child.update!(status: :get_grn)
    end
  end

  test "status 전환이지만 parent_order 없으면 링크 생성 안 함" do
    user  = User.first || User.create!(email: "n@example.com", password: "password123", name: "N")
    order = Order.create!(user: user, title: "Lone", reference_no: "LO-001", status: :pending_po)

    assert_no_difference "OrderLink.count" do
      order.update!(status: :new_po)
    end
  end
```

- [ ] **Step 4.2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/order_test.rb -v`

Expected: 새로 추가한 3개 테스트 FAIL

- [ ] **Step 4.3: 콜백 추가**

`app/models/order.rb` — `include GraphNode` 아래 또는 enum 정의 다음에 추가:

```ruby
class Order < ApplicationRecord
  include GraphNode

  # ... 기존 belongs_to / has_many / enum / scope 모두 그대로 ...

  after_update :create_status_transition_link, if: :saved_change_to_status?

  private

  def create_status_transition_link
    return if parent_order_id.blank?

    prev, curr = saved_change_to_status
    relation = case
               when prev == "pending_po" && curr == "new_po"
                 "confirmed_to"
               when curr == "get_grn"
                 "delivered_as"
               end
    return unless relation

    OrderLink.find_or_create_by!(
      source_type: "Order",
      source_id:   parent_order_id,
      target_type: "Order",
      target_id:   id,
      relation:    relation
    ) do |link|
      link.status     = "confirmed"
      link.confidence = 1.0
      link.metadata   = {
        source:  "system_event",
        trigger: "status_transition:#{prev}->#{curr}"
      }
    end
  end
end
```

> 주의: 기존 `private` 섹션이 있으면 그 아래에 `def create_status_transition_link` 추가. 없으면 새로 `private` 추가. 기존 public 메서드를 실수로 private 시키지 말 것.

- [ ] **Step 4.4: 테스트 재실행 — 통과 확인**

Run: `bin/rails test test/models/order_test.rb -v`

Expected: 새 3개 테스트 PASS, 기존 테스트 0 failures

- [ ] **Step 4.5: 커밋**

```bash
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat(ontology): Order status 전환 → confirmed_to/delivered_as 자동 링크 (M1-4)

pending_po→new_po → confirmed_to.
→get_grn → delivered_as.
parent_order 없으면 생성 안 함. 멱등성 보장."
```

---

## Task 5 — 자동 콜백: `Order.parent_order_id` 변경 → `derived_from`

**Files:**
- Modify: `app/models/order.rb`
- Modify: `test/models/order_test.rb`

- [ ] **Step 5.1: 실패 테스트 작성**

`test/models/order_test.rb` 끝에 추가:

```ruby
  test "parent_order_id 설정 시 derived_from 링크 자동 생성" do
    user   = User.first || User.create!(email: "df@example.com", password: "password123", name: "DF")
    parent = Order.create!(user: user, title: "RFQ",  reference_no: "DF-001", status: :new_rfq)
    child  = Order.create!(user: user, title: "Quote", reference_no: "DF-001", status: :make_quo)

    assert_difference "OrderLink.where(relation: 'derived_from').count", 1 do
      child.update!(parent_order: parent)
    end

    link = OrderLink.where(relation: "derived_from").last
    assert_equal child,  link.source   # 후속 → 원본 방향
    assert_equal parent, link.target
  end

  test "parent_order_id 변경 없으면 derived_from 생성 안 함" do
    user  = User.first || User.create!(email: "df2@example.com", password: "password123", name: "DF2")
    order = Order.create!(user: user, title: "T", reference_no: "DF-002", status: :new_rfq)

    assert_no_difference "OrderLink.where(relation: 'derived_from').count" do
      order.update!(title: "Updated Title")
    end
  end
```

- [ ] **Step 5.2: 테스트 실행 — 실패 확인**

Run: `bin/rails test test/models/order_test.rb -v`

Expected: 새 2개 테스트 FAIL

- [ ] **Step 5.3: 콜백 추가**

`app/models/order.rb` — Task 4에서 추가한 콜백 옆에 추가:

```ruby
  after_update :create_derived_from_link, if: :saved_change_to_parent_order_id?

  private

  # ... create_status_transition_link 그대로 ...

  def create_derived_from_link
    return if parent_order_id.blank?

    OrderLink.find_or_create_by!(
      source_type: "Order",
      source_id:   id,                # 후속(child)
      target_type: "Order",
      target_id:   parent_order_id,   # 원본(parent)
      relation:    "derived_from"
    ) do |link|
      link.status     = "confirmed"
      link.confidence = 1.0
      link.metadata   = {
        source:  "system_event",
        trigger: "parent_order_id_changed"
      }
    end
  end
```

- [ ] **Step 5.4: 테스트 재실행 — 통과 확인**

Run: `bin/rails test test/models/order_test.rb -v`

Expected: 새 2개 PASS, 기존 0 failures

- [ ] **Step 5.5: 전체 모델 테스트 회귀 확인**

Run: `bin/rails test test/models/ -v`

Expected: 0 failures, 0 errors

- [ ] **Step 5.6: 커밋**

```bash
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat(ontology): parent_order_id 변경 → derived_from 자동 링크 (M1-5)

후속(child) → 원본(parent) 방향. 멱등성 보장."
```

---

## Task 6 — 백필 Rake Task (DRY RUN 우선)

**Files:**
- Create: `lib/tasks/order_links.rake`

- [ ] **Step 6.1: rake task 작성**

```ruby
# lib/tasks/order_links.rake
namespace :order_links do
  desc "기존 데이터를 order_links에 백필 (실행 전 dry_run 권장)"
  task backfill: :environment do
    run_backfill(dry_run: false)
  end

  namespace :backfill do
    desc "백필 dry-run — 생성 예정 건수만 출력"
    task dry_run: :environment do
      run_backfill(dry_run: true)
    end
  end

  def run_backfill(dry_run:)
    puts "=" * 60
    puts dry_run ? "DRY RUN — 실제 생성하지 않음" : "백필 실행 — DB에 INSERT"
    puts "=" * 60

    stats = { quoted_as: 0, derived_from: 0, skipped: 0 }

    # 1. 기존 OrderQuote → quoted_as
    OrderQuote.find_each do |q|
      attrs = {
        source_type: "Order", source_id: q.order_id,
        target_type: "OrderQuote", target_id: q.id,
        relation: "quoted_as"
      }
      if OrderLink.exists?(attrs)
        stats[:skipped] += 1
        next
      end
      if dry_run
        stats[:quoted_as] += 1
      else
        OrderLink.create!(attrs.merge(
          status: "confirmed", confidence: 1.0,
          metadata: { source: "backfill", trigger: "OrderQuote_backfill" }
        ))
        stats[:quoted_as] += 1
      end
    end

    # 2. 기존 parent_order_id → derived_from
    Order.where.not(parent_order_id: nil).find_each do |o|
      attrs = {
        source_type: "Order", source_id: o.id,
        target_type: "Order", target_id: o.parent_order_id,
        relation: "derived_from"
      }
      if OrderLink.exists?(attrs)
        stats[:skipped] += 1
        next
      end
      if dry_run
        stats[:derived_from] += 1
      else
        OrderLink.create!(attrs.merge(
          status: "confirmed", confidence: 1.0,
          metadata: { source: "backfill", trigger: "parent_order_backfill" }
        ))
        stats[:derived_from] += 1
      end
    end

    puts ""
    puts "결과:"
    puts "  quoted_as    : #{stats[:quoted_as]}"
    puts "  derived_from : #{stats[:derived_from]}"
    puts "  skipped (already exists): #{stats[:skipped]}"
    puts "=" * 60
  end
end
```

- [ ] **Step 6.2: dry-run 실행**

Run: `bin/rails order_links:backfill:dry_run`

Expected: 통계 출력. 실제 생성 0건. `OrderLink.count` 변화 없음.

- [ ] **Step 6.3: dry-run 후 DB 변화 확인**

Run: `bin/rails runner 'puts "OrderLink count: #{OrderLink.count}"'`

Expected: 0 (또는 콜백으로 생성된 기존 값 그대로 — dry-run으로 증가 없음)

- [ ] **Step 6.4: 실제 백필 실행**

Run: `bin/rails order_links:backfill`

Expected: 통계 출력. quoted_as / derived_from 값이 dry-run과 동일.

- [ ] **Step 6.5: 백필 결과 검증**

Run: `bin/rails runner 'puts OrderLink.group(:relation).count.inspect'`

Expected: `{"quoted_as"=>N, "derived_from"=>M}` 형태 (N, M은 기존 데이터 양에 따름)

- [ ] **Step 6.6: 멱등성 검증 — 두 번째 실행**

Run: `bin/rails order_links:backfill`

Expected: `quoted_as: 0, derived_from: 0, skipped: N+M` (전부 skip)

- [ ] **Step 6.7: 커밋**

```bash
git add lib/tasks/order_links.rake
git commit -m "feat(ontology): order_links 백필 rake task (M1-6)

dry_run 모드 우선. 멱등성 (find_or_create_by 패턴).
quoted_as / derived_from 두 종류 백필."
```

---

## Task 7 — Drawer Detail 탭 임시 텍스트 리스트

**Files:**
- Create: `app/views/orders/_drawer_links.html.erb`
- Modify: `app/views/orders/_drawer.html.erb` (또는 detail tab partial — 아래 Step 7.1에서 정확한 파일 확인)

- [ ] **Step 7.1: 정확한 Drawer 파일 식별**

Run: `find app/views/orders -name "*drawer*" -o -name "*detail*" | head -10`

기대 출력: drawer partial 경로. 결과를 보고 아래 Step 7.3에서 수정할 정확한 파일을 결정한다. 일반적으로 `app/views/orders/_drawer.html.erb` 또는 `app/views/orders/_drawer_detail.html.erb`.

- [ ] **Step 7.2: partial 작성**

```erb
<%# app/views/orders/_drawer_links.html.erb %>
<%# Drawer Detail 탭에 임시 표시. M2에서 Cytoscape 시각화로 교체 예정. %>
<div class="mt-4 p-3 border border-gray-300 rounded-lg bg-white">
  <div class="flex items-center justify-between mb-2">
    <h4 class="text-sm font-semibold text-gray-900">
      📊 연결된 거래
      <span class="text-xs font-normal text-gray-600">
        (<%= @order.outgoing_links.confirmed.count + @order.incoming_links.confirmed.count %>)
      </span>
    </h4>
    <span class="text-xs text-gray-500">M1 · 텍스트 미리보기</span>
  </div>

  <% confirmed_out = @order.outgoing_links.confirmed.includes(:target) %>
  <% confirmed_in  = @order.incoming_links.confirmed.includes(:source) %>

  <% if confirmed_out.empty? && confirmed_in.empty? %>
    <p class="text-xs text-gray-500">아직 연결된 거래가 없습니다.</p>
  <% else %>
    <ul class="space-y-1 text-sm text-gray-900">
      <% confirmed_out.each do |link| %>
        <li>
          <span class="inline-block px-2 py-0.5 rounded text-xs font-semibold"
                style="background:#1E3A5F;color:white;">
            <%= link.relation %>
          </span>
          →
          <span class="text-gray-900">
            <%= link.target_type %> #<%= link.target_id %>
            <% if link.target.respond_to?(:reference_no) && link.target.reference_no.present? %>
              <span class="text-gray-600">(<%= link.target.reference_no %>)</span>
            <% end %>
          </span>
        </li>
      <% end %>
      <% confirmed_in.each do |link| %>
        <li>
          <span class="inline-block px-2 py-0.5 rounded text-xs font-semibold"
                style="background:#00A1E0;color:white;">
            ← <%= link.relation %>
          </span>
          <span class="text-gray-900">
            <%= link.source_type %> #<%= link.source_id %>
            <% if link.source.respond_to?(:reference_no) && link.source.reference_no.present? %>
              <span class="text-gray-600">(<%= link.source.reference_no %>)</span>
            <% end %>
          </span>
        </li>
      <% end %>
    </ul>
  <% end %>
</div>
```

> brand-dna 준수: solid 배경 배지(#1E3A5F / #00A1E0) + white 텍스트, border-gray-300, text-sm 본문. 투명 배지/연한 테두리 금지 규칙 준수.

- [ ] **Step 7.3: Drawer Detail 탭에 partial 렌더링 추가**

Step 7.1에서 식별한 파일을 열어, Detail 탭의 본문 마지막 부근(또는 적절한 위치)에 아래 한 줄을 삽입:

```erb
<%= render "orders/drawer_links" %>
```

> 컨트롤러에서 `@order` 가 이미 set 되어 있어야 함. Drawer가 turbo-frame으로 로드된다면 해당 컨트롤러 액션(`show` 등)을 확인하고 set 상태 보장.

- [ ] **Step 7.4: 서버 시작 + 수동 검증**

Run: `bin/rails server -p 3000 -d`

브라우저에서 `http://localhost:3000` 접속 → 로그인 → 칸반 → Order 카드 클릭 → Drawer 열림 → Detail 탭에서 "📊 연결된 거래" 박스 확인.

기대:
- 링크가 있는 Order → 리스트 표시
- 링크가 없는 Order → "아직 연결된 거래가 없습니다."
- 콘솔 0 에러

- [ ] **Step 7.5: 회귀 — 기존 Drawer 동작 확인**

같은 Drawer에서 Comment 탭, Attachments 탭, History 탭을 한 번씩 클릭. 모두 정상 동작 확인.

- [ ] **Step 7.6: 커밋**

```bash
git add app/views/orders/_drawer_links.html.erb \
        app/views/orders/_drawer.html.erb  # 또는 식별한 실제 파일
git commit -m "feat(ontology): Drawer Detail 탭에 연결된 거래 텍스트 리스트 (M1-7)

M1 임시 UI. M2에서 Cytoscape 시각화로 교체 예정.
brand-dna 준수: solid 배지, border-gray-300, text-sm."
```

---

## Task 8 — M1 종합 검증 + 회귀 + 푸시

**Files:** (변경 없음, 검증 단계)

- [ ] **Step 8.1: 전체 테스트 실행**

Run: `bin/rails test`

Expected: 0 failures, 0 errors. 새로 추가한 11개 케이스 모두 PASS, 기존 테스트 회귀 0건.

- [ ] **Step 8.2: 데이터 상태 점검**

Run: `bin/rails runner '
puts "OrderLink total: #{OrderLink.count}"
puts "by relation: #{OrderLink.group(:relation).count.inspect}"
puts "by status: #{OrderLink.group(:status).count.inspect}"
'`

Expected: total > 0, relation별 분포 출력, 모두 status = "confirmed".

- [ ] **Step 8.3: 신규 OrderQuote 자동 콜백 수동 검증**

Run: `bin/rails runner '
o = Order.first
before = OrderLink.count
OrderQuote.create!(order: o, supplier_name: "Smoke Test", total_amount: 100)
puts "before=#{before}, after=#{OrderLink.count}, diff=#{OrderLink.count - before}"
'`

> `OrderQuote` 필수 필드는 schema에 맞춰 보정. 핵심 검증은 `diff == 1`.

Expected: `diff=1`

- [ ] **Step 8.4: 마이그레이션 롤백 가능성 점검 (안전성 검증)**

Run: `bin/rails db:migrate:status | tail -5`

Expected: `up    20260408120000  Create order links` 표시. 롤백 시도는 하지 말 것 (데이터 손실 위험).

- [ ] **Step 8.5: M1 완료 자가 체크리스트**

Spec 섹션 6.M1의 검증 게이트:
- [ ] 마이그레이션 dev 적용 → 백필 dry-run → 백필 실행 → 100% 성공
- [ ] 신규 OrderQuote 생성 시 자동 link 1건 생성 (Step 8.3 검증)
- [ ] 기존 칸반/Drawer 회귀 0건 (Step 8.1 + Step 7.5 수동)
- [ ] `OrderLink.confirmed.count > 0` (Step 8.2)

전부 체크되면 진행.

- [ ] **Step 8.6: harness 이슈 결과 기록**

Run:
```bash
bash .claude/hooks/on_complete.sh ISS-ONTOLOGY-M1 GENERATE_CODE \
  '{"files_created":["db/migrate/20260408120000_create_order_links.rb","app/models/order_link.rb","app/models/concerns/graph_node.rb","lib/tasks/order_links.rake","app/views/orders/_drawer_links.html.erb"],"files_modified":["app/models/order.rb","app/models/order_quote.rb"],"tests_added":11,"order_links_count":'"$(bin/rails runner 'print OrderLink.count')"'}'
```

> 이슈 ID는 registry.json에 없으면 hook이 자동 무시. 결과 기록 목적.

- [ ] **Step 8.7: 푸시 (자동)**

마지막 커밋 후 git push는 PostToolUse hook이 자동 실행한다. 별도 명령 불필요.

확인:
Run: `git log --oneline -8`

Expected: M1-1 ~ M1-7 + (있다면 M1-8) 7~8개 커밋이 보임.

---

## M1 완료 후 다음 단계

- M2 (Drawer Flow 탭 + Cytoscape) 별도 plan 작성: `docs/superpowers/plans/2026-04-XX-procurement-ontology-m2.md`
- Phase C(RAG) 진입 게이트는 M3 완료 + `OrderLink.count >= 100` + 대표님 확인

---

## Self-Review 결과

**1. Spec coverage** (spec 4 + 6.M1 항목 → task 매핑):
- ✅ `order_links` 마이그레이션 → Task 1
- ✅ `OrderLink` 모델 → Task 1
- ✅ `GraphNode` concern → Task 2
- ✅ `Order`/`OrderQuote` include → Task 2
- ✅ 자동 콜백 4종 (`quoted_as`/`confirmed_to`/`delivered_as`/`derived_from`) → Task 3, 4, 5
- ✅ 백필 rake task (dry-run 우선) → Task 6
- ✅ Drawer Detail 임시 텍스트 리스트 → Task 7
- ✅ 모델 테스트 5케이스 → Task 1 (실제 6케이스로 강화됨)
- ✅ 검증 게이트 → Task 8

**2. Placeholder scan**: TBD/TODO 0건. 모든 코드 블록 완성. 단 Step 7.1과 8.3에서 "schema에 맞춰 보정"이라는 표현이 있는데, 이는 plan 작성 시점에 OrderQuote 필수 필드를 100% 알 수 없어 명시적으로 가드함 — placeholder가 아님.

**3. Type consistency**:
- `OrderLink::RELATIONS` 5종 (`derived_from`/`quoted_as`/`confirmed_to`/`delivered_as`/`references`) — Task 1, 3, 4, 5에서 사용된 이름 일치 ✅
- `outgoing_links`/`incoming_links`/`linked_nodes` — Task 2에서 정의, Task 7에서 사용 일치 ✅
- `metadata: { source:, trigger: }` 형식 — Task 3, 4, 5, 6 일관 ✅
- `status: "confirmed"` 기본값 — 모든 자동 콜백에서 일관 ✅

**모든 검증 통과. plan 작성 완료.**
