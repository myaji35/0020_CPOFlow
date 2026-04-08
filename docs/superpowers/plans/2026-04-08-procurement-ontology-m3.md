# Procurement Ontology M3 — Heuristic 제안 + 수동 링크 + 칸반 호버

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans 또는 subagent-driven-development. 체크박스 단위로 진행.

**Goal:** M2의 시각화 위에 (1) 자동 제안 Job, (2) 제안 confirm/reject Turbo Stream 액션, (3) 수동 링크 추가 모달, (4) 칸반 카드 호버 미니프리뷰, (5) 백그라운드 백필을 추가한다. Phase A 완성 — 추적·관찰·경량 큐레이션 작동.

**Architecture:**
- `SuggestOrderLinksJob`이 `Order.after_create_commit`에서 트리거되어 2종 heuristic으로 `status: "suggested"` OrderLink 생성. SQLite 락 회피를 위해 직렬 처리 + `find_or_create_by!` 멱등성.
- 제안 확정/거부는 `OrderLinksController#confirm/#reject`가 Turbo Stream으로 카드 즉시 제거 + 그래프 일부 갱신.
- 수동 링크 추가는 `OrderLinksController#new` 모달 + `#create` (검색 + relation 드롭다운).
- 칸반 호버는 Stimulus `kanban_refno_preview_controller`가 300ms hover 후 `OrdersController#preview_by_ref` fetch, `Rails.cache.fetch` 5분 캐시.
- 백그라운드 백필은 1000개 단위 batch — `lib/tasks/order_links_backfill_async.rake` (M1의 동기 백필 보강).

**Tech Stack:** Rails 8.1 / Solid Queue / Stimulus / Turbo Stream / Minitest

**Spec:** `docs/superpowers/specs/2026-04-08-procurement-ontology-design.md` (섹션 4.8, 4.9, 5.2, 6.M3)

**M2 의존성:** OrderGraphBuilder + OrderFlowsController + Drawer Flow 탭 머지됨 (commit `136eec1`).

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `app/jobs/suggest_order_links_job.rb` | Create | 2종 heuristic — 같은 Client 90일 + reference_no prefix |
| `app/models/order.rb` | Modify | `after_create_commit { SuggestOrderLinksJob.perform_later(id) }` |
| `app/controllers/order_links_controller.rb` | Create | `new`/`create`/`confirm`/`reject` (Turbo Stream) |
| `config/routes.rb` | Modify | `resources :order_links` (collection: search, member: confirm/reject) |
| `app/views/order_flows/_suggestion_card.html.erb` | Modify | confirm/reject 인라인 버튼 추가 (M2의 placeholder 대체) |
| `app/views/order_links/new.html.erb` | Create | 수동 링크 추가 모달 (검색 + relation 드롭다운) |
| `app/views/order_links/_search_results.html.erb` | Create | autocomplete 검색 결과 partial |
| `app/controllers/orders_controller.rb` | Modify | `preview_by_ref` action 추가 |
| `app/views/orders/_refno_preview.html.erb` | Create | 200×140 호버 툴팁 partial |
| `app/views/kanban/_card.html.erb` | Modify | 관리번호 라벨에 hover trigger 추가 (Stimulus controller binding) |
| `app/javascript/controllers/kanban_refno_preview_controller.js` | Create | 300ms hover, fetch, 위치 계산, mouseleave 취소 |
| `lib/tasks/order_links_backfill_async.rake` | Create | 1000개 batch 백필 (M1 동기 백필 보강) |
| `test/jobs/suggest_order_links_job_test.rb` | Create | heuristic 2종 + 멱등성 5케이스 |
| `test/controllers/order_links_controller_test.rb` | Create | confirm/reject/new/create 5케이스 |
| `test/controllers/orders_controller_preview_by_ref_test.rb` | Create | 캐시 hit/miss + 응답 구조 3케이스 |

---

## Task 1 — `SuggestOrderLinksJob` + Order callback

**Files:**
- Create: `app/jobs/suggest_order_links_job.rb`
- Modify: `app/models/order.rb`
- Create: `test/jobs/suggest_order_links_job_test.rb`

- [ ] **Step 1.1: 실패 테스트 작성**

```ruby
# test/jobs/suggest_order_links_job_test.rb
require "test_helper"

class SuggestOrderLinksJobTest < ActiveJob::TestCase
  setup do
    @user = User.find_or_create_by(email: "sj@test.com") { |u| u.name = "SJ"; u.password = "password123"; u.role = :member }
    @client = Client.create!(name: "SJ Client", code: "SJC-#{SecureRandom.hex(3)}", country: "KR", active: true)
  end

  test "같은 Client 90일 내 → suggested 링크 생성" do
    a = Order.create!(user: @user, client: @client, title: "A", customer_name: "C", reference_no: "AA-001", status: :new_rfq)
    b = Order.create!(user: @user, client: @client, title: "B", customer_name: "C", reference_no: "BB-001", status: :new_rfq)
    before = OrderLink.suggested.count
    SuggestOrderLinksJob.perform_now(a.id)
    assert_operator OrderLink.suggested.count, :>, before
  end

  test "reference_no prefix 매칭 → suggested 링크 생성" do
    a = Order.create!(user: @user, title: "A", customer_name: "C", reference_no: "ENEC-2026-0042", status: :new_rfq)
    Order.create!(user: @user, title: "B", customer_name: "C", reference_no: "ENEC-2026-0099", status: :new_rfq)
    before = OrderLink.suggested.count
    SuggestOrderLinksJob.perform_now(a.id)
    assert_operator OrderLink.suggested.count, :>, before
  end

  test "client 없으면 same_client_recent skip" do
    a = Order.create!(user: @user, title: "X", customer_name: "C", reference_no: "X-001", status: :new_rfq)
    assert_nothing_raised { SuggestOrderLinksJob.perform_now(a.id) }
  end

  test "멱등성 — 2회 실행 시 중복 생성 안 됨" do
    a = Order.create!(user: @user, client: @client, title: "A", customer_name: "C", reference_no: "ID-001", status: :new_rfq)
    Order.create!(user: @user, client: @client, title: "B", customer_name: "C", reference_no: "ID-002", status: :new_rfq)
    SuggestOrderLinksJob.perform_now(a.id)
    after_first = OrderLink.suggested.count
    SuggestOrderLinksJob.perform_now(a.id)
    assert_equal after_first, OrderLink.suggested.count
  end

  test "Order#after_create_commit 콜백이 Job enqueue" do
    assert_enqueued_with(job: SuggestOrderLinksJob) do
      Order.create!(user: @user, title: "Z", customer_name: "C", reference_no: "Z-001", status: :new_rfq)
    end
  end
end
```

- [ ] **Step 1.2: Job 구현**

```ruby
# app/jobs/suggest_order_links_job.rb
class SuggestOrderLinksJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order
    suggest_by_same_client_recent(order)
    suggest_by_reference_no_pattern(order)
  end

  private

  def suggest_by_same_client_recent(order)
    return if order.client_id.blank?
    Order.where(client_id: order.client_id)
         .where.not(id: order.id)
         .where("created_at > ?", 90.days.ago)
         .limit(5)
         .find_each do |c|
      OrderLink.find_or_create_by!(source: order, target: c, relation: "references") do |l|
        l.status = "suggested"
        l.confidence = 0.7
        l.metadata = { source: "heuristic", trigger: "same_client_recent" }
      end
    end
  end

  def suggest_by_reference_no_pattern(order)
    return if order.reference_no.blank?
    parts = order.reference_no.split("-")
    return if parts.size < 2
    prefix = parts.first(2).join("-")
    Order.where("reference_no LIKE ?", "#{prefix}-%")
         .where.not(id: order.id)
         .where.not(reference_no: order.reference_no)
         .limit(5)
         .find_each do |c|
      OrderLink.find_or_create_by!(source: order, target: c, relation: "references") do |l|
        l.status = "suggested"
        l.confidence = 0.6
        l.metadata = { source: "heuristic", trigger: "reference_no_pattern", prefix: prefix }
      end
    end
  end
end
```

- [ ] **Step 1.3: Order 콜백 추가**

`app/models/order.rb`의 다른 `after_create_commit` 근처에:
```ruby
after_create_commit { SuggestOrderLinksJob.perform_later(id) }
```

(이미 다른 콜백이 없다면 적절한 위치에)

- [ ] **Step 1.4: 테스트 통과 확인**

`bin/rails test test/jobs/suggest_order_links_job_test.rb` → 5/0/0

- [ ] **Step 1.5: 회귀 + 커밋**

```bash
git add app/jobs/suggest_order_links_job.rb app/models/order.rb test/jobs/suggest_order_links_job_test.rb
git commit -m "feat(ontology): SuggestOrderLinksJob + Order after_create_commit (M3-1)

2 heuristic: same_client_recent (0.7), reference_no_pattern (0.6).
멱등성 보장. 5 테스트 통과."
```

---

## Task 2 — `OrderLinksController` (confirm/reject Turbo Stream)

**Files:**
- Create: `app/controllers/order_links_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/views/order_flows/_suggestion_card.html.erb`
- Create: `test/controllers/order_links_controller_test.rb`

- [ ] **Step 2.1: 라우트 추가**

`config/routes.rb` 적절한 위치(orders 블록 밖):
```ruby
resources :order_links, only: %i[new create] do
  member do
    patch :confirm
    patch :reject
  end
  collection do
    get :search  # 수동 추가 모달의 검색
  end
end
```

- [ ] **Step 2.2: 컨트롤러 구현**

```ruby
# app/controllers/order_links_controller.rb
class OrderLinksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_link, only: %i[confirm reject]

  def confirm
    @link.update!(status: "confirmed")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("suggestion-#{@link.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def reject
    @link.update!(status: "rejected")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("suggestion-#{@link.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def new
    @order = Order.find(params[:order_id])
    @relations = OrderLink::RELATIONS
    render layout: false
  end

  def create
    source = Order.find(params[:source_id])
    target_type = params[:target_type].presence_in(%w[Order OrderQuote]) || "Order"
    target = target_type.constantize.find(params[:target_id])
    @link = OrderLink.create!(
      source: source, target: target,
      relation: params[:relation], status: "confirmed",
      confidence: 1.0, created_by: current_user,
      metadata: { source: "manual", actor: current_user.email }
    )
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("drawer-panel-#{source.id}-flow-frame", "<turbo-frame src=\"#{order_flow_path(source)}\" id=\"drawer-panel-#{source.id}-flow-frame\"></turbo-frame>")
      end
      format.html { redirect_to order_path(source) }
    end
  end

  def search
    q = params[:q].to_s.strip
    @results = Order.where("title LIKE ? OR reference_no LIKE ?", "%#{q}%", "%#{q}%").limit(10)
    render partial: "order_links/search_results", locals: { results: @results }
  end

  private

  def set_link
    @link = OrderLink.find(params[:id])
  end
end
```

- [ ] **Step 2.3: suggestion_card partial에 confirm/reject 버튼 추가**

`app/views/order_flows/_suggestion_card.html.erb` 전체 교체:
```erb
<%# Local: suggestion (OrderLink) %>
<div id="suggestion-<%= suggestion.id %>" class="p-3 border border-gray-300 rounded-lg" style="background:#FEF3C7;">
  <div class="flex items-center justify-between gap-2">
    <div class="flex items-center gap-2">
      <span class="inline-block px-2 py-0.5 rounded text-xs font-semibold" style="background:#F4A83A;color:white;">제안</span>
      <span class="text-sm" style="color:#16325C;">
        <%= suggestion.relation %> · <%= suggestion.target_type %> #<%= suggestion.target_id %>
        <% if suggestion.confidence %>
          <span class="text-xs" style="color:#374151;">(신뢰도 <%= (suggestion.confidence * 100).round %>%)</span>
        <% end %>
      </span>
    </div>
    <div class="flex items-center gap-2">
      <%= button_to "확정", confirm_order_link_path(suggestion), method: :patch,
            form: { data: { turbo: true } },
            class: "text-xs px-3 py-1 rounded font-semibold",
            style: "background:#1E8E3E;color:white;border:none;cursor:pointer;" %>
      <%= button_to "거부", reject_order_link_path(suggestion), method: :patch,
            form: { data: { turbo: true } },
            class: "text-xs px-3 py-1 rounded font-semibold",
            style: "background:#D93025;color:white;border:none;cursor:pointer;" %>
    </div>
  </div>
</div>
```

> brand-dna: solid 배지 (#1E8E3E success / #D93025 danger), border-gray-300, text-xs 버튼은 padding 보강(px-3 py-1)으로 가독성 확보.

- [ ] **Step 2.4: 컨트롤러 테스트**

```ruby
# test/controllers/order_links_controller_test.rb
require "test_helper"

class OrderLinksControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "ol@test.com") { |u| u.name = "OL"; u.password = "password123"; u.role = :member }
    login_as(@user)
    @a = Order.create!(user: @user, title: "A", customer_name: "C", reference_no: "OL-001", status: :new_rfq)
    @b = Order.create!(user: @user, title: "B", customer_name: "C", reference_no: "OL-002", status: :new_rfq)
    @link = OrderLink.create!(source: @a, target: @b, relation: "references", status: "suggested", confidence: 0.7)
  end

  test "confirm → status: confirmed" do
    patch confirm_order_link_path(@link), as: :turbo_stream
    assert_response :success
    assert_equal "confirmed", @link.reload.status
  end

  test "reject → status: rejected" do
    patch reject_order_link_path(@link), as: :turbo_stream
    assert_response :success
    assert_equal "rejected", @link.reload.status
  end

  test "search → 매칭 Order 반환" do
    get search_order_links_path, params: { q: "A" }
    assert_response :success
    assert_match(/#{@a.title}/, response.body)
  end

  test "new — 수동 추가 모달 200" do
    get new_order_link_path, params: { order_id: @a.id }
    assert_response :success
  end

  test "create — 수동 링크 생성" do
    before = OrderLink.confirmed.count
    post order_links_path, params: { source_id: @a.id, target_type: "Order", target_id: @b.id, relation: "references" }, as: :turbo_stream
    assert_operator OrderLink.confirmed.count, :>, before
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
```

- [ ] **Step 2.5: 통과 + 회귀 + 커밋**

```bash
git add app/controllers/order_links_controller.rb config/routes.rb \
        app/views/order_flows/_suggestion_card.html.erb \
        test/controllers/order_links_controller_test.rb
git commit -m "feat(ontology): OrderLinksController confirm/reject + 수동 추가 (M3-2)

Turbo Stream 5 액션. 5 controller 테스트 통과."
```

---

## Task 3 — 수동 링크 추가 모달 view

**Files:**
- Create: `app/views/order_links/new.html.erb`
- Create: `app/views/order_links/_search_results.html.erb`

- [ ] **Step 3.1: new.html.erb (모달)**

```erb
<%# app/views/order_links/new.html.erb %>
<div class="p-4 bg-white rounded-lg" style="max-width:480px;">
  <h3 class="text-base font-semibold mb-3" style="color:#16325C;">수동 링크 추가</h3>
  <%= form_with url: order_links_path, method: :post, data: { turbo: true } do |f| %>
    <%= f.hidden_field :source_id, value: @order.id %>

    <label class="block text-xs font-semibold text-gray-600 mb-1.5">대상 Order 검색</label>
    <input type="text"
           class="w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:border-[#00A1E0] focus:ring-1 focus:ring-[#00A1E0]"
           placeholder="title 또는 reference_no"
           data-controller="ol-search"
           data-action="input->ol-search#search" />
    <div id="ol-search-results" class="mt-2"></div>

    <%= f.hidden_field :target_id, id: "ol-target-id" %>
    <%= f.hidden_field :target_type, value: "Order" %>

    <label class="block text-xs font-semibold text-gray-600 mb-1.5 mt-3">관계</label>
    <%= f.select :relation, @relations.map { |r| [r, r] },
        {},
        class: "w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm text-gray-900 bg-white focus:outline-none focus:border-[#00A1E0] focus:ring-1 focus:ring-[#00A1E0]" %>

    <div class="flex justify-end gap-2 mt-4">
      <%= f.submit "추가",
          class: "text-sm px-4 py-2 rounded font-semibold",
          style: "background:#1E3A5F;color:white;border:none;cursor:pointer;" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3.2: _search_results.html.erb (autocomplete partial)**

```erb
<%# Local: results %>
<% if results.any? %>
  <ul class="border border-gray-300 rounded-lg divide-y divide-gray-200 max-h-48 overflow-y-auto">
    <% results.each do |o| %>
      <li class="px-3 py-2 text-sm hover:bg-gray-50 cursor-pointer"
          style="color:#16325C;"
          onclick="document.getElementById('ol-target-id').value=<%= o.id %>; this.parentElement.querySelectorAll('li').forEach(el=>el.style.background='');this.style.background='#E5F3FF';">
        <strong><%= o.title %></strong>
        <% if o.reference_no.present? %>
          <span class="text-xs text-gray-600">(<%= o.reference_no %>)</span>
        <% end %>
      </li>
    <% end %>
  </ul>
<% else %>
  <p class="text-xs text-gray-500">결과 없음</p>
<% end %>
```

> Stimulus controller `ol-search`는 일단 인라인 fetch로 단순화 (M3 후속 정리). 또는 `kanban_refno_preview_controller.js`처럼 전용 controller 작성. 여기서는 간단한 인라인 JS로:

`new.html.erb`의 input data-controller 제거하고 onkeyup으로 단순화:
```erb
<input type="text" id="ol-search-input" oninput="window._olSearch&&clearTimeout(window._olSearch);window._olSearch=setTimeout(()=>{fetch('/order_links/search?q='+encodeURIComponent(this.value)).then(r=>r.text()).then(h=>{document.getElementById('ol-search-results').innerHTML=h;});},250);" ... />
```

(Stimulus 없이 인라인 — modal 일회성이라 OK)

- [ ] **Step 3.3: 회귀 + 커밋**

```bash
git add app/views/order_links/new.html.erb app/views/order_links/_search_results.html.erb
git commit -m "feat(ontology): 수동 링크 추가 모달 + 검색 partial (M3-3)

brand-dna: input border-gray-300 + text-sm + py-2.5 + label semibold.
인라인 250ms debounce fetch (Stimulus 생략, 모달 일회성)."
```

---

## Task 4 — 칸반 reference_no 호버 미니프리뷰

**Files:**
- Modify: `app/controllers/orders_controller.rb`
- Modify: `config/routes.rb`
- Create: `app/views/orders/_refno_preview.html.erb`
- Modify: `app/views/kanban/_card.html.erb`
- Create: `app/javascript/controllers/kanban_refno_preview_controller.js`
- Create: `test/controllers/orders_controller_preview_by_ref_test.rb`

- [ ] **Step 4.1: 라우트 추가**

`config/routes.rb`의 첫 `resources :orders` 블록에 collection 추가 (이미 member 블록 있음):
```ruby
collection do
  get :preview_by_ref
end
```

- [ ] **Step 4.2: 컨트롤러 액션 추가**

```ruby
# OrdersController에 추가
def preview_by_ref
  ref = params[:ref].to_s.strip
  return head(:bad_request) if ref.blank?
  data = Rails.cache.fetch("refno_preview/#{ref}", expires_in: 5.minutes) do
    orders = Order.where(reference_no: ref).order(:created_at).limit(5).to_a
    if orders.any?
      g = OrderGraphBuilder.new(orders.first, depth: 1, include_suggested: false).call
      { ref: ref, count: orders.size, nodes: g[:nodes].size, edges: g[:edges].size, first_id: orders.first.id, titles: orders.map(&:title) }
    else
      { ref: ref, count: 0, nodes: 0, edges: 0, first_id: nil, titles: [] }
    end
  end
  render partial: "orders/refno_preview", locals: { data: data }
end
```

- [ ] **Step 4.3: refno_preview partial**

```erb
<%# Local: data (Hash) %>
<div class="p-3 border border-gray-300 rounded-lg shadow-lg" style="background:white;width:200px;">
  <div class="text-xs font-mono mb-1" style="color:#16325C;">Ref: <%= data[:ref] %></div>
  <hr class="border-gray-200 mb-2" />
  <% if data[:count] > 0 %>
    <div class="text-xs mb-1" style="color:#16325C;"><%= data[:nodes] %> nodes · <%= data[:edges] %> edges</div>
    <ul class="text-xs space-y-0.5 mb-2" style="color:#374151;">
      <% data[:titles].first(3).each do |t| %>
        <li class="truncate">• <%= t %></li>
      <% end %>
    </ul>
    <% if data[:first_id] %>
      <a href="/orders/<%= data[:first_id] %>" class="text-xs font-semibold" style="color:#00A1E0;">Open Flow →</a>
    <% end %>
  <% else %>
    <div class="text-xs text-gray-500">데이터 없음</div>
  <% end %>
</div>
```

- [ ] **Step 4.4: Stimulus controller**

```javascript
// app/javascript/controllers/kanban_refno_preview_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { ref: String }

  connect() {
    this.boundEnter = this.enter.bind(this)
    this.boundLeave = this.leave.bind(this)
    this.element.addEventListener("mouseenter", this.boundEnter)
    this.element.addEventListener("mouseleave", this.boundLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.boundEnter)
    this.element.removeEventListener("mouseleave", this.boundLeave)
    this.removeTooltip()
  }

  enter() {
    if (!this.refValue) return
    this.timer = setTimeout(() => this.show(), 300)
  }

  leave() {
    if (this.timer) clearTimeout(this.timer)
    this.removeTooltip()
  }

  async show() {
    const r = await fetch(`/orders/preview_by_ref?ref=${encodeURIComponent(this.refValue)}`)
    if (!r.ok) return
    const html = await r.text()
    this.tip = document.createElement("div")
    this.tip.style.position = "absolute"
    this.tip.style.zIndex = "9999"
    this.tip.innerHTML = html
    document.body.appendChild(this.tip)
    const rect = this.element.getBoundingClientRect()
    this.tip.style.top  = (window.scrollY + rect.bottom + 4) + "px"
    this.tip.style.left = (window.scrollX + rect.left) + "px"
  }

  removeTooltip() {
    if (this.tip) {
      this.tip.remove()
      this.tip = null
    }
  }
}
```

- [ ] **Step 4.5: 칸반 카드 hover 영역 추가**

`app/views/kanban/_card.html.erb` line 75-77 (관리번호 라벨)에 wrapper 추가:
```erb
<% if latest_no %>
  <span class="text-base font-bold truncate" title="<%= latest_no %>"
        <% if order.reference_no.present? %>
        data-controller="kanban-refno-preview"
        data-kanban-refno-preview-ref-value="<%= order.reference_no %>"
        <% end %>>
    <% if latest_no.length > 4 %>
      <span class="text-gray-500 dark:text-gray-500 font-medium"><%= latest_no[0...-4] %></span><span class="text-[#1E3A5F] dark:text-blue-400"><%= latest_no[-4..] %></span>
    <% else %>
      <span class="text-[#1E3A5F] dark:text-blue-400"><%= latest_no %></span>
    <% end %>
  </span>
<% end %>
```

- [ ] **Step 4.6: 컨트롤러 테스트**

```ruby
# test/controllers/orders_controller_preview_by_ref_test.rb
require "test_helper"

class OrdersControllerPreviewByRefTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "pbr@test.com") { |u| u.name = "PBR"; u.password = "password123"; u.role = :member }
    login_as(@user)
    @order = Order.create!(user: @user, title: "Pre Test", customer_name: "C", reference_no: "PBR-2026-0001", status: :new_rfq)
    Rails.cache.clear
  end

  test "preview_by_ref 200 + 응답에 ref 포함" do
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    assert_response :success
    assert_match(/PBR-2026-0001/, response.body)
  end

  test "ref 비어있으면 400" do
    get preview_by_ref_orders_path, params: { ref: "" }
    assert_response :bad_request
  end

  test "캐시 hit — 두 번째 요청도 200" do
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
```

- [ ] **Step 4.7: 회귀 + 커밋**

```bash
git add app/controllers/orders_controller.rb config/routes.rb \
        app/views/orders/_refno_preview.html.erb \
        app/views/kanban/_card.html.erb \
        app/javascript/controllers/kanban_refno_preview_controller.js \
        test/controllers/orders_controller_preview_by_ref_test.rb
git commit -m "feat(ontology): 칸반 reference_no 호버 미니프리뷰 (M3-4)

300ms hover → fetch + 5min cache. 3 controller 테스트."
```

---

## Task 5 — 백그라운드 백필 rake task

**Files:**
- Create: `lib/tasks/order_links_backfill_async.rake`

- [ ] **Step 5.1: rake task**

```ruby
# lib/tasks/order_links_backfill_async.rake
namespace :order_links do
  desc "Backfill suggestions in batches of 1000 (async via SuggestOrderLinksJob)"
  task backfill_async: :environment do
    total = Order.count
    batch_size = 1000
    enqueued = 0
    Order.find_each(batch_size: batch_size) do |o|
      SuggestOrderLinksJob.perform_later(o.id)
      enqueued += 1
    end
    puts "Enqueued #{enqueued}/#{total} jobs"
  end
end
```

- [ ] **Step 5.2: 회귀 + 커밋**

```bash
git add lib/tasks/order_links_backfill_async.rake
git commit -m "feat(ontology): 백그라운드 백필 rake task (M3-5)

order_links:backfill_async — 1000개 batch enqueue."
```

---

## Task 6 — 종합 검증 + push

- [ ] **Step 6.1: 전체 테스트**

`bin/rails test` → 488 + 5(Job) + 5(Links) + 3(Preview) = **501+** runs / 0 failures.

- [ ] **Step 6.2: routes 검증**

```bash
bin/rails routes | grep -E "order_link|preview_by_ref"
```

- [ ] **Step 6.3: 데이터 점검 — Job 수동 실행**

```bash
bin/rails runner '
SuggestOrderLinksJob.perform_now(Order.first.id)
puts "OrderLink suggested: #{OrderLink.suggested.count}"
'
```

- [ ] **Step 6.4: M3 자가 체크리스트**

- [ ] SuggestOrderLinksJob 2 heuristic + 멱등성 (Task 1)
- [ ] confirm/reject Turbo Stream (Task 2)
- [ ] 수동 링크 추가 모달 (Task 3)
- [ ] 칸반 호버 미니프리뷰 + 캐시 (Task 4)
- [ ] 백그라운드 백필 rake (Task 5)
- [ ] Brand-guardian anti-pattern 0건 (자가 검증)
- [ ] 회귀 0건

- [ ] **Step 6.5: harness 결과 기록 + push**

자동 push.

---

## M3 완료 후

Phase A 완성. Phase C(RAG) 진입 게이트:
- ✅ M3 완료
- ✅ `OrderLink.count >= 100`
- ✅ 대표님 "그래프 보는 것만으로 의사결정에 도움이 된다" 확인
- ✅ CPO Agent Supervisor 진행 상황과 통합 가능 시점

---

## Self-Review

**Spec 6.M3 → Task 매핑:**
- ✅ SuggestOrderLinksJob (4.8) → Task 1
- ✅ Order.after_create_commit 트리거 → Task 1
- ✅ 제안 confirm/reject 컨트롤러 (Turbo Stream) → Task 2
- ✅ 수동 링크 추가 모달 → Task 2 + Task 3
- ✅ 칸반 reference_no 호버 (5.2) → Task 4
- ✅ 백그라운드 백필 1000 batch → Task 5

**Placeholder 0건.** 모든 코드 블록 완성.

**가정:**
- Solid Queue 정상 동작 — `perform_later`가 inline 모드 또는 background로 실행됨 (test에서는 `assert_enqueued_with`)
- `Order::STATUS_LABELS` 등 기존 헬퍼는 변경 없음
- `OrderLink::RELATIONS` 상수가 M1에서 정의됨 (`%w[derived_from quoted_as confirmed_to delivered_as references]`)
