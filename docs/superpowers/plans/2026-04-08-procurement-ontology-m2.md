# Procurement Ontology M2 — Drawer Flow 탭 + Cytoscape 시각화

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M1에서 구축한 `OrderLink` 데이터를 시각화한다. `OrderGraphBuilder` 서비스가 BFS로 그래프를 빌드하고, `OrderFlowsController#show`가 turbo-frame partial을 반환하며, Drawer에 5번째 "Flow" 탭을 추가해 Cytoscape.js + dagre로 렌더링한다. M1의 임시 텍스트 리스트는 유지(빠른 폴백). 제안 카드(`status: "suggested"`)는 partial로 표시하되 confirm/reject 컨트롤러는 M3에서 추가.

**Architecture:**
- 서비스 계층 (`OrderGraphBuilder`)이 polymorphic OrderLink BFS + reference_no/FK 가상 링크 합성을 담당. 컨트롤러/뷰는 출력 hash(`{nodes:, edges:}`)만 소비.
- Drawer Flow 탭은 Stimulus(`order_flow_controller`)가 데이터 속성에서 그래프 JSON을 읽어 Cytoscape 인스턴스를 lazy 생성. Turbo navigation 시 `disconnect()`에서 `cy.destroy()`로 누수 방지.
- Cytoscape는 CDN(unpkg) lazy load — 첫 Drawer 열림 시점에만 로드.

**Tech Stack:** Rails 8.1 / Stimulus / Cytoscape.js 3.x + cytoscape-dagre (CDN, ~370KB) / Turbo / Minitest

**Spec:** `docs/superpowers/specs/2026-04-08-procurement-ontology-design.md` (섹션 4.6, 5.1, 6.M2)

**M1 의존성:** OrderLink 모델 + GraphNode concern + 자동 콜백이 main에 머지됨 (커밋 `8308a76`).

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `app/services/order_graph_builder.rb` | Create | BFS depth 1~3 + 가상 링크 합성 + 명시 링크 우선 중복 제거 |
| `app/controllers/order_flows_controller.rb` | Create | `show` — `@graph` 빌드 + partial 렌더 (`layout: false`) |
| `config/routes.rb` | Modify | `resource :flow, only: [:show], controller: "order_flows"` nested |
| `app/views/order_flows/show.html.erb` | Create | Cytoscape canvas + 데이터 속성(JSON) + Stimulus controller binding |
| `app/views/order_flows/_suggestion_card.html.erb` | Create | suggested 링크 카드 (M2는 표시만, M3에서 confirm/reject 액션) |
| `app/javascript/controllers/order_flow_controller.js` | Create | Stimulus — Cytoscape lifecycle, 노드 click → Turbo navigation |
| `app/views/orders/_drawer_content.html.erb` | Modify | 5번째 탭 "Flow" 추가 + 패널 turbo-frame `id="drawer-panel-{id}-flow"` |
| `app/views/layouts/application.html.erb` | Modify | Cytoscape + dagre CDN script (defer) |
| `test/services/order_graph_builder_test.rb` | Create | 5케이스 — depth 1/2/3, reference_no 가상, FK 가상, 명시-가상 중복 제거 |
| `test/controllers/order_flows_controller_test.rb` | Create | `#show` 200 응답 + 노드/엣지 데이터 포함 |

---

## Task 1 — `OrderGraphBuilder` 서비스 (실패 테스트 우선)

**Files:**
- Create: `app/services/order_graph_builder.rb`
- Create: `test/services/order_graph_builder_test.rb`

- [ ] **Step 1.1: 실패 테스트 작성 — `order_graph_builder_test.rb`**

```ruby
# test/services/order_graph_builder_test.rb
require "test_helper"

class OrderGraphBuilderTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "gb@test.com", password: "password123", name: "GB")
    @client = Client.first || Client.create!(name: "C1", company_name: "C1", country: "KR")
    @rfq = Order.create!(user: @user, client: @client, title: "RFQ", reference_no: "GB-001", status: :new_rfq)
    @po  = Order.create!(user: @user, client: @client, title: "PO",  reference_no: "GB-001", status: :new_po, parent_order: @rfq)
    OrderLink.create!(source: @rfq, target: @po, relation: "confirmed_to", status: "confirmed", confidence: 1.0)
  end

  test "depth 1 — root와 직접 연결만 포함" do
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    node_ids = g[:nodes].map { |n| n[:id] }
    assert_includes node_ids, "Order:#{@rfq.id}"
    assert_includes node_ids, "Order:#{@po.id}"
    assert_equal true, g[:nodes].find { |n| n[:id] == "Order:#{@rfq.id}" }[:current]
  end

  test "depth 2 — 손자 노드 포함" do
    grand = Order.create!(user: @user, client: @client, title: "GRN", reference_no: "GB-001", status: :get_grn, parent_order: @po)
    OrderLink.create!(source: @po, target: grand, relation: "delivered_as", status: "confirmed", confidence: 1.0)
    g = OrderGraphBuilder.new(@rfq, depth: 2).call
    assert_includes g[:nodes].map { |n| n[:id] }, "Order:#{grand.id}"
  end

  test "MAX_DEPTH=3 강제 — 4 입력해도 3으로 cap" do
    builder = OrderGraphBuilder.new(@rfq, depth: 99)
    assert_equal 3, builder.send(:depth)
  end

  test "reference_no 가상 링크 합성 — 같은 reference_no 노드 자동 연결" do
    sibling = Order.create!(user: @user, client: @client, title: "Sibling", reference_no: "GB-001", status: :new_rfq)
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    virtual_edges = g[:edges].select { |e| e[:virtual] }
    assert virtual_edges.any? { |e| e[:relation] == "references" }, "reference_no 가상 엣지 없음"
  end

  test "FK 가상 링크 — Client 가상 노드 합성" do
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    assert g[:nodes].any? { |n| n[:type] == "Client" }, "Client 가상 노드 없음"
  end

  test "명시 링크 우선 — 같은 (source,target,relation) 가상 링크는 생략" do
    # @rfq → @po confirmed_to 는 명시 링크. reference_no 가상 합성으로 references 가 추가될 수 있음.
    # 명시 confirmed_to가 있으면 같은 키의 가상 confirmed_to는 생성되지 않아야 함.
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    confirmed_to_edges = g[:edges].select { |e| e[:relation] == "confirmed_to" && e[:from] == "Order:#{@rfq.id}" && e[:to] == "Order:#{@po.id}" }
    assert_equal 1, confirmed_to_edges.size
    assert_equal false, confirmed_to_edges.first[:virtual]
  end
end
```

Run: `bin/rails test test/services/order_graph_builder_test.rb`
Expected: 모두 FAIL (서비스 미구현).

- [ ] **Step 1.2: 서비스 구현 — `order_graph_builder.rb`**

```ruby
# app/services/order_graph_builder.rb
class OrderGraphBuilder
  MAX_DEPTH = 3

  def initialize(root, depth: MAX_DEPTH, include_suggested: false)
    @root = root
    @depth = [[depth.to_i, 1].max, MAX_DEPTH].min
    @include_suggested = include_suggested
    @nodes = {}  # id => node hash
    @edges = []  # array of edge hashes
    @explicit_keys = Set.new  # "source_id|target_id|relation"
  end

  def call
    add_node(@root, current: true)
    bfs_explicit
    synthesize_reference_no_virtual
    synthesize_fk_virtual
    { nodes: @nodes.values, edges: @edges }
  end

  private

  attr_reader :depth

  def status_filter
    @include_suggested ? %w[confirmed suggested] : %w[confirmed]
  end

  def bfs_explicit
    frontier = [[@root, 0]]
    visited = Set.new(["#{@root.class.name}:#{@root.id}"])
    until frontier.empty?
      node, d = frontier.shift
      next if d >= @depth
      out_links = OrderLink.where(source_type: node.class.name, source_id: node.id, status: status_filter)
      in_links  = OrderLink.where(target_type: node.class.name, target_id: node.id, status: status_filter)
      (out_links + in_links).each do |link|
        other = (link.source_type == node.class.name && link.source_id == node.id) ? link.target : link.source
        next if other.nil?
        key = "#{other.class.name}:#{other.id}"
        add_node(other) unless @nodes.key?(key)
        push_explicit_edge(link)
        unless visited.include?(key)
          visited << key
          frontier << [other, d + 1]
        end
      end
    end
  end

  def push_explicit_edge(link)
    from = "#{link.source_type}:#{link.source_id}"
    to   = "#{link.target_type}:#{link.target_id}"
    @explicit_keys << "#{from}|#{to}|#{link.relation}"
    @edges << {
      from: from, to: to,
      relation: link.relation, status: link.status,
      virtual: false,
      confidence: link.confidence
    }
  end

  def synthesize_reference_no_virtual
    return if @nodes.empty?
    refs = @nodes.values.map { |n| n[:reference_no] }.compact.uniq
    refs.each do |ref|
      same = @nodes.values.select { |n| n[:reference_no] == ref && n[:type] == "Order" }
      next if same.size < 2
      same.combination(2).each do |a, b|
        push_virtual_edge(a[:id], b[:id], "references")
      end
    end
  end

  def synthesize_fk_virtual
    @nodes.values.dup.each do |n|
      next unless n[:type] == "Order"
      order = Order.find_by(id: n[:id].split(":").last)
      next unless order
      [
        [order.client,   "Client",   "requested_by"],
        [order.supplier, "Supplier", "quoted_by"],
        [order.project,  "Project",  "for_project"]
      ].each do |obj, type, relation|
        next unless obj
        vnode_id = "#{type}:#{obj.id}"
        unless @nodes.key?(vnode_id)
          @nodes[vnode_id] = {
            id: vnode_id, type: type, status: nil, reference_no: nil,
            current: false, virtual: true,
            label: obj.respond_to?(:name) ? obj.name : "#{type}##{obj.id}"
          }
        end
        push_virtual_edge(n[:id], vnode_id, relation)
      end
    end
  end

  def push_virtual_edge(from, to, relation)
    return if @explicit_keys.include?("#{from}|#{to}|#{relation}")
    return if @edges.any? { |e| e[:from] == from && e[:to] == to && e[:relation] == relation }
    @edges << {
      from: from, to: to,
      relation: relation, status: "virtual",
      virtual: true, confidence: nil
    }
  end

  def add_node(obj, current: false)
    id = "#{obj.class.name}:#{obj.id}"
    @nodes[id] = {
      id: id,
      type: obj.class.name,
      status: obj.respond_to?(:status) ? obj.status : nil,
      reference_no: obj.respond_to?(:reference_no) ? obj.reference_no : nil,
      current: current,
      virtual: false,
      label: node_label(obj)
    }
  end

  def node_label(obj)
    if obj.respond_to?(:title) && obj.title.present?
      obj.title
    elsif obj.respond_to?(:reference_no) && obj.reference_no.present?
      obj.reference_no
    else
      "#{obj.class.name}##{obj.id}"
    end
  end
end
```

> `Set` require: Ruby 3.2+ 자동 로드. 만약 `NameError: Set` 뜨면 파일 상단에 `require "set"` 추가.

- [ ] **Step 1.3: 테스트 통과 확인**

Run: `bin/rails test test/services/order_graph_builder_test.rb`
Expected: 6 runs / 0 failures.

- [ ] **Step 1.4: 회귀 — 전체 테스트**

Run: `bin/rails test 2>&1 | tail -5`
Expected: 485+ runs / 0 failures (M1 479 + 신규 6).

- [ ] **Step 1.5: 커밋**

```bash
git add app/services/order_graph_builder.rb test/services/order_graph_builder_test.rb
git commit -m "feat(ontology): OrderGraphBuilder 서비스 (M2-1)

BFS depth 1~3 + reference_no 가상 + FK 가상 합성.
명시 링크 우선 중복 제거. 6 테스트 통과."
```

---

## Task 2 — 라우트 + `OrderFlowsController#show`

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/order_flows_controller.rb`
- Create: `test/controllers/order_flows_controller_test.rb`

- [ ] **Step 2.1: 라우트 추가**

`config/routes.rb` 첫 번째 `resources :orders` 블록(line 28~44) 안에 nested resource 추가:

```ruby
resources :orders do
  # ... 기존 nested ...
  resource :flow, only: [:show], controller: "order_flows"
  member do
    # ... 기존 member ...
  end
end
```

확인:
```bash
bin/rails routes | grep order_flow
```
Expected: `order_flow GET /orders/:order_id/flow(.:format) order_flows#show`

- [ ] **Step 2.2: 컨트롤러 테스트 — `order_flows_controller_test.rb`**

```ruby
# test/controllers/order_flows_controller_test.rb
require "test_helper"

class OrderFlowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "fc@test.com", password: "password123", name: "FC")
    sign_in @user
    @order = Order.create!(user: @user, title: "Flow Test", reference_no: "FC-001", status: :new_rfq)
  end

  test "GET /orders/:id/flow returns 200 + nodes" do
    get order_flow_path(@order)
    assert_response :success
    assert_match /Order:#{@order.id}/, response.body
  end

  test "응답에 cytoscape data 속성 포함" do
    get order_flow_path(@order)
    assert_match /data-order-flow-graph-value/, response.body
  end
end
```

> `sign_in`: Devise test helpers 가정. `test_helper.rb`에 이미 include 되어 있음 (M1 테스트가 동일 패턴 사용).

- [ ] **Step 2.3: 컨트롤러 구현**

```ruby
# app/controllers/order_flows_controller.rb
class OrderFlowsController < ApplicationController
  before_action :authenticate_user!

  def show
    @order = Order.find(params[:order_id])
    @graph = OrderGraphBuilder.new(@order, depth: 3, include_suggested: true).call
    @suggestions = OrderLink.suggested.where(
      "(source_type = ? AND source_id = ?) OR (target_type = ? AND target_id = ?)",
      @order.class.name, @order.id, @order.class.name, @order.id
    )
    render layout: false
  end
end
```

- [ ] **Step 2.4: show.html.erb 최소 구현 (Task 3에서 본격 작성, 여기선 테스트 통과용)**

```erb
<%# app/views/order_flows/show.html.erb %>
<turbo-frame id="drawer-panel-<%= @order.id %>-flow-frame">
  <div data-controller="order-flow"
       data-order-flow-graph-value="<%= @graph.to_json %>"
       data-order-flow-order-id-value="<%= @order.id %>">
    <div data-order-flow-target="canvas" class="w-full" style="height:420px;background:#F3F2F2;border:1px solid #d1d5db;border-radius:8px;"></div>
  </div>
</turbo-frame>
```

- [ ] **Step 2.5: 컨트롤러 테스트 통과 확인**

Run: `bin/rails test test/controllers/order_flows_controller_test.rb`
Expected: 2 runs / 0 failures.

- [ ] **Step 2.6: 회귀**

Run: `bin/rails test 2>&1 | tail -5`
Expected: 487+ / 0 failures.

- [ ] **Step 2.7: 커밋**

```bash
git add config/routes.rb app/controllers/order_flows_controller.rb \
        app/views/order_flows/show.html.erb test/controllers/order_flows_controller_test.rb
git commit -m "feat(ontology): OrderFlowsController + 라우트 + 최소 view (M2-2)

GET /orders/:id/flow → @graph 빌드 + turbo-frame partial.
2 controller 테스트 통과."
```

---

## Task 3 — Drawer 5번째 "Flow" 탭 추가

**Files:**
- Modify: `app/views/orders/_drawer_content.html.erb`

- [ ] **Step 3.1: 탭 배열에 'flow' 추가**

`app/views/orders/_drawer_content.html.erb` line 11~17, 5개 탭 배열에 추가:

```erb
<% [
  ['detail',      '상세'],
  ['tasks',       '태스크'],
  ['comments',    '코멘트'],
  ['attachments', '첨부파일'],
  ['history',     '히스토리'],
  ['flow',        '플로우']
].each_with_index do |(tab_id, label), i| %>
```

- [ ] **Step 3.2: 새 탭 패널 추가**

drawer 파일 끝부분(history 패널 다음)에 추가:

```erb
<%# ══════════════════════════════════════════════════════════
    탭 패널 6: 플로우 (Cytoscape, M2)
══════════════════════════════════════════════════════════ %>
<div id="drawer-panel-<%= order.id %>-flow" class="p-6 hidden">
  <turbo-frame id="drawer-panel-<%= order.id %>-flow-frame"
               src="<%= order_flow_path(order) %>"
               loading="lazy">
    <div class="flex items-center justify-center py-12 text-sm text-gray-500">
      <svg class="animate-spin w-5 h-5 mr-2" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10" stroke-opacity="0.3"/>
        <path d="M12 2a10 10 0 0 1 10 10"/>
      </svg>
      플로우 그래프 로딩…
    </div>
  </turbo-frame>
</div>
```

> `loading="lazy"`: Drawer가 열리고 Flow 탭이 클릭될 때까지 fetch 안 함. 첫 Drawer 첫 렌더 비용 0.

`switchDrawerTab` JS 함수가 5개 탭 ID 하드코딩 여부 확인 필수:

Run:
```bash
grep -n "switchDrawerTab" app/views/orders/_drawer_content.html.erb app/javascript/**/*.js 2>/dev/null | head -5
```

만약 함수가 탭 ID 배열을 하드코딩하면 'flow' 추가. 동적이면 변경 불필요.

- [ ] **Step 3.3: 수동 검증 — 서버 시작**

Run: `bin/rails server -p 3000 -d`

브라우저:
1. localhost:3000 로그인
2. 칸반 → Order 카드 클릭 → Drawer 열림
3. "플로우" 탭 클릭 → turbo-frame이 `/orders/:id/flow` fetch → 회색 캔버스(420px) 표시 + 콘솔 0 에러

> 이 시점에서는 그래프 그림은 없음 (Stimulus controller 미구현). 캔버스 + JSON 데이터 속성만 확인.

- [ ] **Step 3.4: 회귀 + 커밋**

Run: `bin/rails test 2>&1 | tail -5`

```bash
git add app/views/orders/_drawer_content.html.erb
git commit -m "feat(ontology): Drawer Flow 탭 추가 (M2-3)

6번째 탭 'flow' + lazy turbo-frame.
M1 텍스트 리스트는 detail 탭에 유지(폴백)."
```

---

## Task 4 — Cytoscape CDN + Stimulus controller

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/javascript/controllers/order_flow_controller.js`

- [ ] **Step 4.1: CDN script 추가 (defer)**

`app/views/layouts/application.html.erb`의 `<head>` 끝부분(다른 stylesheet/javascript 태그 근처):

```erb
<script src="https://unpkg.com/cytoscape@3.30.2/dist/cytoscape.min.js" defer></script>
<script src="https://unpkg.com/dagre@0.8.5/dist/dagre.min.js" defer></script>
<script src="https://unpkg.com/cytoscape-dagre@2.5.0/cytoscape-dagre.js" defer></script>
```

> 버전 고정 (latest 사용 금지) — Cytoscape API breaking 방지.

- [ ] **Step 4.2: Stimulus controller**

```javascript
// app/javascript/controllers/order_flow_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas"]
  static values  = { graph: Object, orderId: Number }

  connect() {
    if (typeof cytoscape === "undefined") {
      // CDN 미로드 → 폴백: 짧은 재시도 1회
      setTimeout(() => this.render(), 300)
      return
    }
    this.render()
  }

  disconnect() {
    if (this.cy) {
      this.cy.destroy()
      this.cy = null
    }
  }

  render() {
    if (typeof cytoscape === "undefined") {
      this.canvasTarget.innerHTML = '<div class="p-4 text-sm text-gray-600">Cytoscape CDN 로드 실패</div>'
      return
    }
    if (typeof cytoscapeDagre !== "undefined") {
      cytoscape.use(cytoscapeDagre)
    }
    const data = this.graphValue
    const elements = [
      ...data.nodes.map(n => ({
        data: { id: n.id, label: n.label || n.id, type: n.type, current: n.current, virtual: n.virtual }
      })),
      ...data.edges.map((e, i) => ({
        data: { id: `e${i}`, source: e.from, target: e.to, relation: e.relation, virtual: e.virtual }
      }))
    ]

    this.cy = cytoscape({
      container: this.canvasTarget,
      elements: elements,
      layout: { name: (typeof cytoscapeDagre !== "undefined") ? "dagre" : "breadthfirst", rankDir: "TB", padding: 20 },
      style: [
        {
          selector: "node",
          style: {
            "background-color": ele => this.nodeColor(ele.data("type")),
            "label": "data(label)",
            "color": "#16325C",
            "font-size": "10px",
            "text-valign": "bottom",
            "text-margin-y": 4,
            "width": 36, "height": 36,
            "border-width": 1,
            "border-color": "#9CA3AF"
          }
        },
        {
          selector: "node[?current]",
          style: {
            "border-width": 3,
            "border-color": "#00A1E0",
            "width": 48, "height": 48
          }
        },
        {
          selector: "node[?virtual]",
          style: {
            "border-style": "dashed",
            "background-color": "#9CA3AF",
            "opacity": 0.7
          }
        },
        {
          selector: "edge",
          style: {
            "width": 2,
            "line-color": "#1E3A5F",
            "target-arrow-color": "#1E3A5F",
            "target-arrow-shape": "triangle",
            "curve-style": "bezier",
            "label": "data(relation)",
            "font-size": "8px",
            "color": "#16325C",
            "text-background-color": "#ffffff",
            "text-background-opacity": 1,
            "text-background-padding": 2
          }
        },
        {
          selector: "edge[?virtual]",
          style: {
            "line-style": "dashed",
            "line-color": "#9CA3AF",
            "target-arrow-color": "#9CA3AF",
            "width": 1
          }
        }
      ]
    })

    this.cy.on("tap", "node", evt => {
      const id = evt.target.data("id")
      const [type, oid] = id.split(":")
      if (type === "Order" && Number(oid) !== this.orderIdValue) {
        // 같은 Drawer 안에서 컨텍스트 전환 — 새 turbo-frame fetch
        const frame = document.getElementById(`drawer-panel-${this.orderIdValue}-flow-frame`)
        if (frame) {
          frame.src = `/orders/${oid}/flow`
        }
      }
    })
  }

  nodeColor(type) {
    return {
      "Order":     "#1E3A5F",
      "OrderQuote":"#F4A83A",
      "Client":    "#9CA3AF",
      "Supplier":  "#9CA3AF",
      "Project":   "#9CA3AF"
    }[type] || "#6B7280"
  }
}
```

- [ ] **Step 4.3: importmap 또는 controllers/index.js 등록 확인**

Run:
```bash
grep -rn "order_flow\|order-flow" app/javascript/controllers/index.js app/javascript/controllers/application.js 2>/dev/null | head -5
ls app/javascript/controllers/ | head -20
```

만약 자동 등록(stimulus-loading eager) 사용 중이면 별도 작업 불필요. importmap이라면 `app/javascript/controllers/index.js`에 다음 추가:

```javascript
import OrderFlowController from "./order_flow_controller"
application.register("order-flow", OrderFlowController)
```

- [ ] **Step 4.4: 수동 검증 — 그래프 렌더링**

Run: `bin/rails restart` (또는 server 재시작)

브라우저:
1. Drawer 열기 → "플로우" 탭 클릭
2. Cytoscape canvas에 노드/엣지 렌더링 확인
3. 노드 hover → 커서 변화
4. 다른 Order 노드 클릭 → turbo-frame src 변경 → 새 그래프 렌더링
5. 콘솔 0 에러

스크린샷: `cpoflow-m2-flow-tab.png`

- [ ] **Step 4.5: 회귀 + 커밋**

```bash
git add app/views/layouts/application.html.erb app/javascript/controllers/order_flow_controller.js \
        app/javascript/controllers/index.js  # (수정한 경우)
git commit -m "feat(ontology): Cytoscape CDN + order_flow Stimulus controller (M2-4)

CDN lazy: cytoscape@3.30.2 + dagre@0.8.5 + cytoscape-dagre@2.5.0.
brand-dna 색상: Order #1E3A5F, OrderQuote #F4A83A, 가상 #9CA3AF.
노드 클릭 → 같은 Drawer 안 컨텍스트 전환 (turbo-frame src 갱신)."
```

---

## Task 5 — show.html.erb 본 구현 + 제안 카드 partial

**Files:**
- Modify: `app/views/order_flows/show.html.erb`
- Create: `app/views/order_flows/_suggestion_card.html.erb`

- [ ] **Step 5.1: show.html.erb 본 구현**

```erb
<%# app/views/order_flows/show.html.erb %>
<turbo-frame id="drawer-panel-<%= @order.id %>-flow-frame">
  <div class="space-y-3">
    <%# 제안 카드 (M3에서 confirm/reject 인라인 액션 추가 예정) %>
    <% if @suggestions.any? %>
      <div class="space-y-2">
        <% @suggestions.each do |s| %>
          <%= render "order_flows/suggestion_card", suggestion: s %>
        <% end %>
      </div>
    <% end %>

    <%# Cytoscape 캔버스 %>
    <div data-controller="order-flow"
         data-order-flow-graph-value="<%= @graph.to_json %>"
         data-order-flow-order-id-value="<%= @order.id %>">
      <div data-order-flow-target="canvas"
           class="w-full"
           style="height:420px;background:#F3F2F2;border:1px solid #d1d5db;border-radius:8px;"></div>
    </div>

    <%# 범례 %>
    <div class="flex flex-wrap gap-3 text-xs text-gray-600">
      <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full" style="background:#1E3A5F;"></span>Order</span>
      <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full" style="background:#F4A83A;"></span>Quote</span>
      <span class="flex items-center gap-1"><span class="w-3 h-3 rounded-full border border-dashed border-gray-400" style="background:#9CA3AF;"></span>가상 (Client/Supplier/Project)</span>
      <span class="flex items-center gap-1"><span class="inline-block w-4 h-0.5 bg-[#1E3A5F]"></span>확정</span>
      <span class="flex items-center gap-1"><span class="inline-block w-4 h-0.5 border-t border-dashed border-gray-400"></span>가상</span>
    </div>
  </div>
</turbo-frame>
```

- [ ] **Step 5.2: 제안 카드 partial — `_suggestion_card.html.erb`**

```erb
<%# app/views/order_flows/_suggestion_card.html.erb %>
<%# Local: suggestion %>
<div class="p-3 border border-gray-300 rounded-lg" style="background:#FEF3C7;">
  <div class="flex items-center justify-between gap-2">
    <div class="flex items-center gap-2">
      <span class="inline-block px-2 py-0.5 rounded text-xs font-semibold" style="background:#F4A83A;color:white;">
        제안
      </span>
      <span class="text-sm" style="color:#16325C;">
        <%= suggestion.relation %> · <%= suggestion.target_type %> #<%= suggestion.target_id %>
        <% if suggestion.confidence %>
          <span class="text-xs text-gray-700">(신뢰도 <%= (suggestion.confidence * 100).round %>%)</span>
        <% end %>
      </span>
    </div>
    <span class="text-xs text-gray-500">M3에서 확정/거부</span>
  </div>
</div>
```

> brand-dna 준수: solid 배경 `#FEF3C7` (투명 X), 솔리드 배지 `#F4A83A` + white 텍스트, `border-gray-300`, `text-sm` 본문, `text-gray-700` (gray-500 이하 금지).

- [ ] **Step 5.3: 컨트롤러 테스트 보강**

```ruby
# test/controllers/order_flows_controller_test.rb 에 추가
test "suggested 링크가 있으면 제안 카드 렌더링" do
  link = OrderLink.create!(
    source: @order, target: @order, relation: "references",
    status: "suggested", confidence: 0.7
  )
  get order_flow_path(@order)
  assert_response :success
  assert_match /제안/, response.body
end
```

> self-loop는 실제로는 없겠지만, 테스트를 위해 source/target 동일 허용 (validation 통과 확인). 실패하면 별도 Order 생성으로 대체.

- [ ] **Step 5.4: 테스트 + 회귀**

Run: `bin/rails test test/controllers/order_flows_controller_test.rb`
Run: `bin/rails test 2>&1 | tail -5`

Expected: controller 3 runs / 0 failures, 전체 488+ / 0 failures.

- [ ] **Step 5.5: 커밋**

```bash
git add app/views/order_flows/show.html.erb app/views/order_flows/_suggestion_card.html.erb \
        test/controllers/order_flows_controller_test.rb
git commit -m "feat(ontology): Flow 탭 본 view + 제안 카드 partial (M2-5)

범례 + 제안 카드 (solid #FEF3C7, brand-dna 준수).
3 controller 테스트 통과."
```

---

## Task 6 — Brand-guardian 검증 + 운영 데이터 5건 시각 검증

**Files:** (변경 없음, 검증 단계)

- [ ] **Step 6.1: brand-dna.json 확인**

Run: `cat .claude/agents/brand-dna.json 2>/dev/null | head -30 || echo "no brand-dna.json"`

존재하면 다음 anti-pattern 체크리스트 자가 검증:
- [ ] 투명 배지(`bg-*-100`, `${color}28` 패턴) 0건 — 모든 배지 solid
- [ ] `border-gray-100` 0건 — 모두 `border-gray-200` 이상
- [ ] `text-gray-500` 이하 본문 0건
- [ ] `text-xs` form input 0건
- [ ] AI slop 패턴 (의미 없는 그라데이션, 떠다니는 카드, 무의미한 이모지) 0건
- [ ] Primary action 1개 (Drawer 안에서 명확)

- [ ] **Step 6.2: 운영 데이터 5개 Order에서 시각 검증**

Run:
```bash
bin/rails runner '
Order.joins("INNER JOIN order_links ON (order_links.source_type=\"Order\" AND order_links.source_id=orders.id) OR (order_links.target_type=\"Order\" AND order_links.target_id=orders.id)").distinct.limit(5).pluck(:id, :title, :reference_no).each { |row| puts row.inspect }
'
```

각 Order 5개에 대해:
1. localhost:3000/orders/:id/flow 직접 접속
2. 응답 200 + Cytoscape canvas 렌더링 + 노드 1개 이상 확인
3. 스크린샷 캡처

- [ ] **Step 6.3: 콘솔 에러 0건 확인**

브라우저 DevTools Console에서 Drawer 열고 Flow 탭 클릭 → 5개 Order 순회 → 0 error / 0 warning(스타일 deprecation 제외).

- [ ] **Step 6.4: 회귀 — 기존 Drawer 4탭 정상 동작**

Detail/Tasks/Comments/Attachments/History 각 탭 1회 클릭 → 모두 정상.

- [ ] **Step 6.5: M1 detail 텍스트 리스트 회귀**

Detail 탭의 "📊 연결된 거래" 박스 여전히 표시 확인 (M2에서 폴백 유지).

---

## Task 7 — M2 종합 검증 + 푸시

**Files:** (검증 단계)

- [ ] **Step 7.1: 전체 테스트**

Run: `bin/rails test`

Expected: 488+ runs / 0 failures.

- [ ] **Step 7.2: routes 검증**

Run: `bin/rails routes | grep -E "order_flow|flow"`

Expected: `order_flow GET /orders/:order_id/flow(.:format) order_flows#show`

- [ ] **Step 7.3: 데이터 점검**

Run:
```bash
bin/rails runner '
puts "OrderLink: #{OrderLink.count} (confirmed=#{OrderLink.confirmed.count}, suggested=#{OrderLink.suggested.count})"
puts "Orders with links: #{Order.joins("INNER JOIN order_links ON (order_links.source_type=\"Order\" AND order_links.source_id=orders.id) OR (order_links.target_type=\"Order\" AND order_links.target_id=orders.id)").distinct.count}"
'
```

- [ ] **Step 7.4: M2 자가 체크리스트**

Spec 6.M2 검증 게이트:
- [ ] OrderGraphBuilder BFS depth 1/2/3 동작 (Task 1 테스트)
- [ ] OrderFlowsController#show 200 응답 (Task 2 테스트)
- [ ] Drawer 6번째 "플로우" 탭 lazy 로드 (Task 3 수동)
- [ ] Cytoscape 렌더링 + 노드 클릭 컨텍스트 전환 (Task 4 수동)
- [ ] 제안 카드 partial 렌더링 (Task 5 테스트)
- [ ] Brand-guardian anti-pattern 0건 (Task 6 자가 검증)
- [ ] 운영 데이터 5건 시각 검증 (Task 6)
- [ ] 기존 Drawer 4탭 회귀 0건 (Task 6)

- [ ] **Step 7.5: harness 결과 기록**

Run:
```bash
bash .claude/hooks/on_complete.sh ISS-ONTOLOGY-M2 GENERATE_CODE \
  '{"files_created":["app/services/order_graph_builder.rb","app/controllers/order_flows_controller.rb","app/views/order_flows/show.html.erb","app/views/order_flows/_suggestion_card.html.erb","app/javascript/controllers/order_flow_controller.js","test/services/order_graph_builder_test.rb","test/controllers/order_flows_controller_test.rb"],"files_modified":["config/routes.rb","app/views/orders/_drawer_content.html.erb","app/views/layouts/application.html.erb"],"tests_added":9}'
```

- [ ] **Step 7.6: 푸시 (자동)**

PostToolUse hook이 자동 push. 확인:

Run: `git log --oneline -8`

Expected: M2-1 ~ M2-5 + (필요 시 M2-6) 5~6개 커밋.

---

## M2 완료 후 다음 단계

- M3 (Heuristic 제안 Job + 수동 링크 + 칸반 호버) 별도 plan 작성: `docs/superpowers/plans/2026-04-XX-procurement-ontology-m3.md`
- M3 완료 + `OrderLink.count >= 100` + 대표님 확인 → Phase C(RAG) 진입 게이트

---

## Self-Review 결과

**1. Spec coverage (spec 6.M2 → task 매핑):**
- ✅ OrderGraphBuilder 서비스 → Task 1
- ✅ OrderFlowsController#show + 라우트 → Task 2
- ✅ Drawer 5번째 탭 → Task 3 (실제 6번째, 기존이 5탭)
- ✅ Cytoscape.js + dagre CDN → Task 4
- ✅ order_flow_controller.js Stimulus → Task 4
- ✅ 제안 카드 partial → Task 5
- ✅ Brand-guardian 검증 → Task 6
- ✅ Drawer 폭에서 노드 시각 검증 → Task 6.2

**2. M3 분리 (이 plan에서 안 함):**
- ❌ SuggestOrderLinksJob — M3
- ❌ 제안 confirm/reject 컨트롤러 (Turbo Stream) — M3
- ❌ 수동 링크 추가 모달 — M3
- ❌ 칸반 reference_no 호버 미니프리뷰 — M3

**3. 가정 (실패 시 보정 필요):**
- Devise `sign_in` 헬퍼 사용 가능 (M1 컨트롤러 테스트가 동일 패턴 사용)
- importmap 또는 stimulus-loading eager 등록 — Task 4.3에서 확인 후 보정
- `Client`, `Supplier`, `Project` 모델에 `name` 메서드 존재 (없으면 `node_label` fallback)
- `switchDrawerTab` JS 함수가 동적 탭 처리 — Task 3.2에서 확인 후 보정

**4. Placeholder 0건.** 모든 코드 블록 완성.
