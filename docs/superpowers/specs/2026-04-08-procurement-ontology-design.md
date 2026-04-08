# Procurement Ontology — 발주 추적·관찰·의사결정 지원

**Status**: Draft
**Date**: 2026-04-08
**Author**: CPOFlow Team (brainstormed via superpowers:brainstorming)
**Phase**: Phase A (3-Phase 로드맵 중 1단계)

---

## 1. 배경 (Why)

CPOFlow는 9단계 칸반(`new_rfq → make_quo → pending_po → new_po → delivery_items → problem → get_grn → give_up → done`)으로 발주 흐름을 관리한다. 그러나 현재 한 거래의 **전체 궤적**(어느 메일에서 시작 → 어느 견적으로 분기 → 어느 PO로 묶임 → 어느 GRN으로 종결)을 한눈에 추적할 방법이 없다.

`Activity` 모델은 단일 Order에 갇혀 있고(from/to status만 기록), `parent_order_id`는 직계 부모-자식 관계만 표현한다. 따라서:

- 발주 담당자는 같은 reference_no를 가진 여러 Order를 칸반에서 그룹으로 보지만, **그 사이의 인과 관계**를 모른다.
- 비정형 참조(예: "이 PO는 저 RFQ를 일부만 따왔다")를 명시할 곳이 없다.
- 미래의 의사결정 지원(RAG, 추론)을 하려 해도 그래프 구조가 없어 불가능하다.

**대표님 요구**: "온톨로지 개념을 도입하고 싶어. 하나의 발주이력을 추적·관찰·의사결정에 도움을 주고 싶어."

## 2. 3-Phase 로드맵

본 스펙은 **Phase A만** 다룬다. B/C는 별도 스펙으로 분리한다.

```
Phase A — 거래 그래프 (Tracking Graph)         [본 스펙]
   "이 RFQ → 견적1, 견적2 → PO → GRN" 흐름을 노드/엣지로 시각화
   목적: 발주 담당자가 한 거래의 전체 궤적을 0.5초 안에 파악

   ↓ 데이터가 쌓이면

Phase C — 의사결정 Copilot (RAG)               [별도 스펙]
   그래프 traversal로 과거 유사 거래를 끌어와 Claude가 답변
   CPO Agent Supervisor와 결합

   ↓ 패턴이 보이면

Phase B — 도메인 지식 그래프 + 추론             [별도 스펙]
   온톨로지 클래스/속성 정의 → 규칙 기반 추론
   AgentInsight 자동 생성 강화
```

**Phase A → C 게이트**: M3 완료 + `OrderLink` 100건 이상 + 대표님이 "그래프만으로 의사결정 도움된다" 확인.
**Phase C → B 게이트**: Phase C 완료 + RAG 안정 운영 + "패턴 자동 발견 needs" 발생.

## 3. 결정 요약 (6개)

| # | 결정 | 근거 |
|---|---|---|
| 1 | Phase A → C → B 순서 | 데이터 → AI → 추론, 가치 검증 단계적 |
| 2 | 노드 = Order/OrderQuote/Email + Client/Supplier/Product/Project (옵션 2) | "한 거래 = 누가/어디서/무엇을" 한 그래프에 수렴 |
| 3 | UX = Drawer "Flow" 탭 (메인) + 칸반 reference_no 호버 미니프리뷰 (보조) | 사용자 동선 안에 그래프, 풀스크린 페이지는 YAGNI |
| 4 | `order_links` 단일 polymorphic 테이블 + 5개 relation + JSON metadata | 기존 FK 무손상, 추가 관계만 명시 저장, RDF 매핑 용이 |
| 5 | 자동(시스템 이벤트) + 추정(heuristic, suggested 상태) + 수동 | 빈약한 그래프 + 정확성의 균형 |
| 6 | reference_no = 가상 링크 (저장 X), `order_links`는 명시 링크 전용 | SSoT 유지, 기존 데이터 0 영향 |

## 4. 데이터 모델

### 4.1 새 테이블 — `order_links`

```ruby
create_table :order_links do |t|
  t.references :source, polymorphic: true, null: false  # Order, OrderQuote, Email...
  t.references :target, polymorphic: true, null: false
  t.string  :relation, null: false
  t.text    :metadata                                   # JSON serialized (SQLite)
  t.string  :status, default: "confirmed"               # confirmed | suggested | rejected
  t.float   :confidence, default: 1.0                   # 0.0 ~ 1.0
  t.references :created_by, foreign_key: { to_table: :users }, null: true
  t.timestamps
end

add_index :order_links, [:source_type, :source_id]
add_index :order_links, [:target_type, :target_id]
add_index :order_links, [:relation, :status]
add_index :order_links,
          [:source_type, :source_id, :target_type, :target_id, :relation],
          unique: true, name: "idx_order_links_unique"
```

### 4.2 Relation 5종

| relation | source → target | 생성 방식 |
|---|---|---|
| `derived_from` | Order(후속) → Order(원본) or Email | 자동 (parent_order_id 변경) |
| `quoted_as` | Order(RFQ) → OrderQuote | 자동 (OrderQuote.after_create_commit) |
| `confirmed_to` | OrderQuote or Order(RFQ) → Order(PO) | 자동 (status `pending_po → new_po`) |
| `delivered_as` | Order(PO) → Order(GRN/SubOrder) | 자동 (status → `get_grn`) |
| `references` | Order ↔ Order (비정형) | 수동 또는 heuristic 추정 |

### 4.3 metadata 예시

```json
{
  "source": "system_event",
  "trigger": "OrderQuote.after_create",
  "evidence": "parent_order_id 매칭",
  "user_note": null
}
```

`source` 값: `system_event` | `heuristic` | `manual`

### 4.4 모델 — `OrderLink`

```ruby
class OrderLink < ApplicationRecord
  belongs_to :source, polymorphic: true
  belongs_to :target, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  RELATIONS = %w[derived_from quoted_as confirmed_to delivered_as references].freeze
  STATUSES  = %w[confirmed suggested rejected].freeze

  validates :relation, inclusion: { in: RELATIONS }
  validates :status,   inclusion: { in: STATUSES }
  validates :confidence, numericality: { in: 0.0..1.0 }

  serialize :metadata, coder: JSON

  scope :confirmed, -> { where(status: "confirmed") }
  scope :suggested, -> { where(status: "suggested") }
  scope :for_node, ->(node) { where(source: node).or(where(target: node)) }
end
```

### 4.5 Concern — `GraphNode`

```ruby
module GraphNode
  extend ActiveSupport::Concern

  included do
    has_many :outgoing_links, as: :source, class_name: "OrderLink", dependent: :destroy
    has_many :incoming_links, as: :target, class_name: "OrderLink", dependent: :destroy
  end

  def linked_nodes(relation: nil, status: "confirmed")
    out = outgoing_links.where(status: status)
    inc = incoming_links.where(status: status)
    out = out.where(relation: relation) if relation
    inc = inc.where(relation: relation) if relation
    (out.map(&:target) + inc.map(&:source)).uniq
  end
end
```

`Order`, `OrderQuote`에 `include GraphNode`. (Phase A 범위에서 `Email`, `Client`, `Supplier`, `Project`는 가상 노드로만 다루므로 include 불필요.)

### 4.6 그래프 빌더 — `OrderGraphBuilder`

`MAX_DEPTH = 3`. `includes(:client, :supplier, :project)`로 N+1 방지.

핵심 로직 3단계:
1. **명시 링크 traversal**: `OrderLink` BFS, root에서 깊이 3까지
2. **reference_no 가상 링크 합성**: 같은 reference_no 노드들끼리 `references` 가상 엣지 추가 (저장 X)
3. **FK 가상 링크 합성**: 각 Order의 `client_id/supplier_id/project_id`를 `requested_by/quoted_by/for_project` 가상 엣지로 추가

**중복 방지 규칙**: 명시 링크가 이미 존재하면 같은 (source, target, relation) 가상 링크는 생략.

출력 형식:
```ruby
{
  nodes: [
    { id: "Order:123", type: "Order", status: "new_po", reference_no: "ENEC-...", current: true, label: "..." },
    ...
  ],
  edges: [
    { from: "Order:123", to: "OrderQuote:45", relation: "quoted_as", status: "confirmed", virtual: false },
    ...
  ]
}
```

### 4.7 자동 링크 콜백

```ruby
# OrderQuote
after_create_commit :create_quoted_link

# Order
after_update :create_status_transition_link, if: :saved_change_to_status?
after_update :create_derived_from_link, if: :saved_change_to_parent_order_id?
```

콜백 4개:
1. `OrderQuote#create_quoted_link` → `source: order(RFQ)`, `target: self(Quote)`, `quoted_as` 1건
2. `Order#create_status_transition_link` (`pending_po → new_po`) → `parent_order(RFQ)` 가 있으면 `source: parent_order`, `target: self(PO)`, `confirmed_to` 1건
3. `Order#create_status_transition_link` (`→ get_grn`) → `parent_order(PO)` 가 있으면 `source: parent_order`, `target: self(GRN/SubOrder)`, `delivered_as` 1건. 만약 PO가 SubOrder를 가지면 PO는 새 GRN을 자식으로 가지므로 `Order` 자기자신이 PO일 때만 트리거됨 — 즉 콜백은 status 전환 노드에서 실행되며 `parent_order_id` 존재가 필수 조건.
4. `Order#create_derived_from_link` → `source: self`, `target: parent_order`, `derived_from` 1건

모두 `find_or_create_by` 멱등성 보장. metadata에 `source: "system_event"`, `trigger: "..."` 기록.

### 4.8 Heuristic 추정 Job

```ruby
class SuggestOrderLinksJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    suggest_by_same_client_recent(order)  # 90일 내 같은 Client → confidence 0.7
    suggest_by_reference_no_pattern(order)  # ENEC-2026-* fuzzy → confidence 0.6
  end

  private

  def suggest_by_same_client_recent(order)
    return if order.client_id.blank?
    Order.where(client_id: order.client_id)
         .where.not(id: order.id)
         .where("created_at > ?", 90.days.ago)
         .limit(5)
         .each do |c|
      OrderLink.find_or_create_by!(source: order, target: c, relation: "references") do |l|
        l.status = "suggested"
        l.confidence = 0.7
        l.metadata = { source: "heuristic", trigger: "same_client_recent" }
      end
    end
  end

  def suggest_by_reference_no_pattern(order)
    return if order.reference_no.blank?
    prefix = order.reference_no.split("-").first(2).join("-")
    Order.where("reference_no LIKE ?", "#{prefix}-%")
         .where.not(id: order.id)
         .where.not(reference_no: order.reference_no)
         .limit(5)
         .each do |c|
      OrderLink.find_or_create_by!(source: order, target: c, relation: "references") do |l|
        l.status = "suggested"
        l.confidence = 0.6
        l.metadata = { source: "heuristic", trigger: "reference_no_pattern", prefix: prefix }
      end
    end
  end
end
```

트리거: 새 Order 생성 시 `after_create_commit { SuggestOrderLinksJob.perform_later(id) }`.
SQLite 락 회피 위해 `unique: true` (Solid Queue 옵션) 또는 직렬화.

### 4.9 자동 정리 Cron

`OrderLink` 중 `status = "suggested" AND confidence < 0.6 AND created_at < 30 days ago` → 자동 reject.

## 5. UX

### 5.1 Drawer "Flow" 탭

**위치**: 기존 4탭(Detail/Comment/Attachments/History) 뒤에 5번째.

**캔버스**: ~680×420px Cytoscape SVG.

**시각 규칙** (brand-dna.json `_status: "active"` 준수):

| 요소 | 스타일 |
|---|---|
| RFQ 노드 | `#00A1E0` (sky blue) |
| Quote 노드 | `#F4A83A` (warning) |
| PO 노드 | `#1E3A5F` (navy, hero) |
| GRN 노드 | `#1E8E3E` (success) |
| Email 노드 | `#6B7280` (gray) |
| Client/Supplier/Project 가상 노드 | `#9CA3AF` 점선 border |
| **현재 노드** | ★ + `border-2 border-[#00A1E0]` + 큰 크기 (시각적 1순위, 0.5초 룰) |
| 확정 엣지 | 실선 `stroke-[#1E3A5F] stroke-width:2` |
| 제안 엣지 | 점선 `stroke-dasharray:4,4 stroke-[#9CA3AF]` |
| 가상 엣지 | 더 가는 점선 `stroke-[#D1D5DB]` + `(virtual)` 라벨 |
| 제안 카드 배경 | solid `#FEF3C7` + 텍스트 `#16325C` (anti-pattern: 투명 배지 금지) |

**인터랙션**:
- 노드 hover → tooltip: Order ID, status, due_date, assignee
- 노드 click → 같은 Drawer 내부에서 해당 Order로 컨텍스트 교체 (Turbo)
- 제안 카드 → `[확정]` `[거부]` 인라인 버튼 → Turbo Stream으로 즉시 제거
- `[+ 수동 링크 추가]` → 검색 모달 (`order-form-autocomplete` 패턴 재사용) → relation 5종 드롭다운

**라이브러리**: Cytoscape.js 3.x + cytoscape-dagre (CDN, ~370KB).
- 이유: 노드 50개 이하 빠름, dagre 자동 layout(TB), Turbo 호환 (`disconnect()`에서 `cy.destroy()`)
- 대안 검토: d3-force (자유 배치, 흐름 표현 부적합), mermaid (정적, 인터랙션 약함) — 둘 다 reject

**라우트**:
```ruby
resources :orders do
  resource :flow, only: [:show], controller: "order_flows"
end
# /orders/:order_id/flow
```

**컨트롤러**:
```ruby
class OrderFlowsController < ApplicationController
  def show
    @order = Order.find(params[:order_id])
    @graph = OrderGraphBuilder.new(@order, depth: 3).call
    @suggestions = OrderLink.suggested.for_node(@order)
    render layout: false
  end
end
```

### 5.2 칸반 reference_no 호버 미니프리뷰

**트리거**: 칸반 카드의 reference_no 라벨 hover 300ms.

**구조** (200×140px 툴팁):
```
Ref: ENEC-2026-0042
─────────────────────
●RFQ ─▶ ●Quote ─▶ ★PO
3 nodes · 2 edges
[Open Flow →]
```

**데이터 소스**: `OrderGraphBuilder` `depth: 1` + filter (같은 reference_no만).

**캐시**: `Rails.cache.fetch("refno_preview/#{ref}", expires_in: 5.minutes)`.

**라우트**:
```ruby
get "orders/preview_by_ref", to: "orders#preview_by_ref"
```

**Stimulus**: `kanban_refno_preview_controller.js` — `mouseenter` 300ms 타이머, `mouseleave` 취소, fetch + 위치 계산.

### 5.3 동선

```
[칸반] reference_no 호버 (300ms)
   ↓
[미니프리뷰 툴팁] 노드 3개 미리보기
   ↓ "Open Flow →" 클릭
[Drawer 열림 + Flow 탭 자동 선택]
   ↓
[Cytoscape 그래프] 노드 클릭 → 컨텍스트 전환
   ↓
[제안 검토] 점선 엣지 + 노란 카드 → 확정/거부
```

## 6. 점진 롤아웃 (3 마일스톤)

### M1 — Skeleton & 자동 링크

**작업**:
1. `order_links` 마이그레이션 + `OrderLink` 모델
2. `GraphNode` concern → `Order`, `OrderQuote`에 include
3. 자동 링크 콜백 4개
4. **데이터 백필 rake task** (`lib/tasks/order_links_backfill.rake`) — DRY RUN 모드 필수
5. `OrderLink` 모델 테스트 5케이스
6. Drawer Detail 탭에 임시 텍스트 리스트 (검증용)

**검증 게이트**:
- 마이그레이션 dev 적용 → 백필 dry-run → 백필 실행 → 100% 성공
- 신규 OrderQuote 생성 시 자동 link 1건 (수동 테스트)
- 기존 칸반/Drawer 회귀 0건

**완료 기준**: `OrderLink.confirmed.count > 0` + 회귀 0건

### M2 — Drawer Flow 탭 + Cytoscape 시각화

**작업**:
1. `OrderGraphBuilder` 서비스
2. `OrderFlowsController#show` + 라우트
3. Drawer 5번째 탭 추가
4. Cytoscape.js + cytoscape-dagre CDN 추가
5. `order_flow_controller.js` (Stimulus)
6. 제안 카드 partial
7. **Brand-guardian 검증 통과**
8. Drawer 폭 720px에서 노드 7개 시각 검증

**검증 게이트**:
- gstack browse로 자동 렌더링 검증 (콘솔 0 에러)
- 노드 클릭 → 컨텍스트 전환 작동
- Brand-guardian DESIGN_FIX 0건
- 대표님 육안 승인

**완료 기준**: 운영 데이터 5개 검증 + 스크린샷 보고

### M3 — Heuristic 제안 + 수동 링크 + 칸반 호버

**작업**:
1. `SuggestOrderLinksJob` (2종 heuristic)
2. Job 트리거 (`Order.after_create_commit`)
3. 제안 확정/거부 컨트롤러 (Turbo Stream)
4. 수동 링크 추가 모달 (검색 + relation 드롭다운)
5. 칸반 reference_no 호버 미니프리뷰
6. 백그라운드 백필 (배치 1000개 단위)

**검증 게이트**:
- 제안 5건 이상 자동 생성 → 확정/거부 작동
- 수동 링크 5종 모두 저장 검증
- N+1 쿼리 0건 (`bullet` gem 또는 로그)
- Brand-guardian 통과
- SQLite 락 이슈 0건

**완료 기준**: Phase A 완성 — 추적·관찰·경량 큐레이션 작동

### M3 후 게이트 (Phase C 진입 조건)

- ✅ M3 완료
- ✅ `OrderLink.count >= 100`
- ✅ 대표님이 "그래프 보는 것만으로 의사결정에 도움이 된다" 확인
- ✅ CPO Agent Supervisor 진행 상황과 통합 가능 시점

## 7. 리스크 & 완화

| 리스크 | 영향 | 완화 |
|---|---|---|
| Cytoscape 번들 크기 (370KB) | Drawer 첫 로드 느려짐 | CDN, Drawer 열 때만 로드 (lazy) |
| Heuristic 제안 폭주 | DB 비대 | `confidence < 0.6` 자동 제외, 30일 이상 unconfirmed 자동 reject cron |
| polymorphic FK 무결성 | 그래프 빌더 크래시 | `OrderLink#source` nil-safe, 손상 링크 자동 reject |
| SQLite 동시쓰기 락 | Job 실패 | `SuggestOrderLinksJob` 직렬화 (Solid Queue `unique: true`) |
| reference_no 가상 + 명시 링크 중복 | UI 혼란 | 빌더가 "명시 링크가 있으면 가상 링크 생략" 규칙 적용 |
| 노드 50개 이상 시 Cytoscape 느림 | UX 저하 | `MAX_DEPTH=3` 강제, 그 이상은 "더 보기" 버튼 |

## 8. 측정 지표

| 지표 | M1 목표 | M2 목표 | M3 목표 |
|---|---|---|---|
| `OrderLink.confirmed.count` | > 0 | > 50 | > 200 |
| `OrderLink.suggested.count` | 0 | 0 | > 30 |
| Brand-guardian DESIGN_FIX | - | 0건 | 0건 |
| 회귀 (기존 칸반/Drawer) | 0건 | 0건 | 0건 |
| Flow 탭 평균 렌더 시간 | - | < 500ms | < 500ms |
| 제안 확정률 | - | - | ≥ 70% |

## 9. 범위 외 (Phase A에서 안 함)

- ❌ Phase B (RDF, 추론 규칙, OWL) — 별도 스펙
- ❌ Phase C (RAG, Claude integration) — 별도 스펙
- ❌ 풀스크린 그래프 페이지 (`/orders/:id/trace`) — 데이터 충분히 쌓인 후 재평가 (YAGNI)
- ❌ Activity 모델 확장 (commented_by, decided_by 등 노드화) — 옵션 3, over-engineering
- ❌ 그래프 export (GraphML, JSON-LD) — Phase B 진입 시
- ❌ Email 모델 신설 — 현재 EmailAccount만 있고 개별 이메일은 Order에 흡수됨, Phase A에서는 가상 노드로만

## 10. 인터페이스 (요약)

**모델**:
- `OrderLink#source`, `#target` (polymorphic), `#relation`, `#status`, `#confidence`, `#metadata`
- `OrderLink.confirmed`, `.suggested`, `.for_node(node)`
- `Order#linked_nodes(relation:, status:)`, `#outgoing_links`, `#incoming_links`
- `OrderQuote#linked_nodes(...)` (동일)

**서비스**:
- `OrderGraphBuilder.new(root_order, depth: 3, include_suggested: true).call` → `{ nodes:, edges: }`

**Job**:
- `SuggestOrderLinksJob.perform_later(order_id)`

**컨트롤러**:
- `OrderFlowsController#show` — Drawer Flow 탭 partial
- `OrderLinksController#confirm`, `#reject`, `#new`, `#create` — 제안/수동 관리
- `OrdersController#preview_by_ref` — 칸반 호버 미니프리뷰

**Stimulus**:
- `order_flow_controller` — Cytoscape lifecycle, 노드 click 이벤트
- `kanban_refno_preview_controller` — 300ms hover, fetch, 캐시

## 11. 테스트 전략

**M1 단위 테스트**:
- `OrderLink` validation (5케이스): relation/status/confidence 범위, polymorphic 양쪽 set
- `OrderQuote.after_create` → `quoted_as` 자동 생성
- `Order` status `pending_po → new_po` → `confirmed_to` 멱등 생성

**M2 통합 테스트**:
- `OrderGraphBuilder` (5케이스): depth 1/2/3, reference_no 가상 합성, FK 가상 합성, 명시-가상 중복 제거
- `OrderFlowsController#show` 응답 200 + JSON 구조 검증

**M3 통합 + system 테스트**:
- `SuggestOrderLinksJob` 멱등성 (같은 Order 2회 실행 → 중복 없음)
- 제안 confirm/reject Turbo Stream 응답
- 칸반 호버 캐시 hit/miss

**Brand-guardian 통과** (M2, M3 필수): 8개 anti-pattern 0건, primary action 1개 존재.

---

**다음 단계**: 본 spec 승인 → `superpowers:writing-plans` 스킬로 M1 구현 계획 작성.
