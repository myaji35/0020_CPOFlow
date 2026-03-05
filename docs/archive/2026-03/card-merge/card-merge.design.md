# card-merge Design Document

> **Summary**: 동일 `reference_no`의 Order를 `parent_order_id`로 연결해 칸반에 메인 카드 1개만 표시하고, 서브 이벤트는 드로어 스레드 탭에 보존한다.
>
> **Plan 문서**: `docs/01-plan/features/card-merge.plan.md`
> **Date**: 2026-03-03
> **Status**: Draft

---

## 1. 현황 분석 (As-Is)

### 1.1 이미 구현된 것 (재사용)

| 항목 | 파일 | 상태 |
|------|------|------|
| `reference_no` 컬럼 + 인덱스 | `db/schema.rb` | ✅ 존재 |
| `by_reference_no` 스코프 | `app/models/order.rb:53` | ✅ 존재 |
| `ReferenceNumberExtractor` | `app/services/gmail/reference_number_extractor.rb` | ✅ 존재 |
| `check_thread_duplicate` | `app/services/gmail/email_to_order_service.rb:150` | ✅ 존재 (부분) |
| 드로어 `thread_orders` UI | `app/views/orders/_drawer_content.html.erb:342` | ✅ 존재 |
| `@thread_orders` 컨트롤러 쿼리 | `app/controllers/orders_controller.rb:53` | ✅ 존재 |

### 1.2 현재 문제점 (Gap)

```
check_thread_duplicate 현재 로직:
  Order.where(reference_no: ref_no).where.not(status: :inbox).exists?

→ inbox 상태끼리는 중복 체크 안 함
→ 동일 reference_no 이메일 3건 모두 inbox 카드로 생성됨
→ parent_order_id 컬럼 미존재 → 메인/서브 구분 불가
→ 칸반에 중복 카드 표시
```

---

## 2. To-Be 설계

### 2.1 데이터 모델 변경

#### 신규 컬럼 (마이그레이션)
```ruby
# 20260303_add_parent_order_id_to_orders.rb
add_column :orders, :parent_order_id, :integer, null: true
add_index  :orders, :parent_order_id
```

> **참고**: `add_foreign_key`는 SQLite MVP 환경에서 생략 (PostgreSQL 전환 시 추가)

#### Order 모델 연관 추가
```ruby
# app/models/order.rb
belongs_to :parent_order, class_name: "Order", optional: true
has_many   :sub_orders,   class_name: "Order", foreign_key: :parent_order_id,
                          dependent: :nullify

scope :root_orders, -> { where(parent_order_id: nil) }
scope :sub_orders_of, ->(id) { where(parent_order_id: id) }
```

#### 상태 정의
| `parent_order_id` | 의미 | 칸반 표시 |
|---|---|---|
| `nil` | 메인(독립) 카드 | 항상 표시 |
| `N` (정수) | 서브 카드 | 숨김 |

---

## 3. 컴포넌트별 변경 설계

### 3.1 EmailToOrderService — 중복 분기 로직

**파일**: `app/services/gmail/email_to_order_service.rb`

#### 변경 전 (현재)
```ruby
def check_thread_duplicate(ref_no, verdict)
  return false if ref_no.blank?
  return false if verdict == :excluded

  Order.where(reference_no: ref_no)
       .where.not(status: %i[inbox])
       .exists?
end
```

#### 변경 후
```ruby
def find_parent_order(ref_no)
  return nil if ref_no.blank?

  # 1순위: inbox 이외 진행 중인 메인 카드
  parent = Order.where(reference_no: ref_no)
                .where(parent_order_id: nil)
                .where.not(status: :inbox)
                .order(created_at: :asc)
                .first
  return parent if parent

  # 2순위: inbox 상태 중 가장 먼저 생성된 메인 카드
  Order.where(reference_no: ref_no)
       .where(parent_order_id: nil)
       .order(created_at: :asc)
       .first
end
```

#### create_order! 분기 추가
```ruby
def create_order!
  return nil if Order.exists?(source_email_id: @email[:id])

  ref_no  = ReferenceNumberExtractor.extract(@email[:subject].to_s, @email[:body].to_s)
  parent  = find_parent_order(ref_no)

  order = Order.new(
    # ... 기존 필드 동일 ...
    reference_no:      ref_no,
    parent_order_id:   parent&.id,          # ← 신규
    status:            :inbox,
  )

  if order.save
    if parent
      # 서브 카드 생성 → 메인 카드에 Activity 추가
      Activity.create!(
        order:  parent,
        user:   @account.user,
        action: "thread_email_received",
        metadata: { sub_order_id: order.id, subject: @email[:subject] }
      )
      Rails.logger.info "[EmailToOrder] Sub-order ##{order.id} linked to parent ##{parent.id}"
    else
      # 기존 로직 동일
      auto_assign_from_history(order)
      Activity.create!(order: order, user: @account.user, action: "auto_created_from_email")
      RfqReplyDraftJob.perform_later(order.id) if verdict == :confirmed && @detection[:is_rfq]
    end
    order
  end
end
```

---

### 3.2 칸반 뷰 — 서브 카드 필터링 + 배지

**파일**: `app/controllers/kanban_controller.rb` (또는 해당 쿼리 위치)

```ruby
# 칸반 쿼리: 서브 카드 제외
@orders = Order.where(parent_order_id: nil)
               .where(status: column_status)
               # ... 기존 필터 동일 ...
```

**파일**: `app/views/kanban/_card.html.erb`

```erb
<%# 서브 카드 배지 %>
<% sub_count = order.sub_orders.count %>
<% if sub_count > 0 %>
  <span class="inline-flex items-center gap-1 text-xs text-gray-500 border border-gray-200 rounded px-1.5 py-0.5">
    <!-- SVG mail-stack icon -->
    +<%= sub_count %>
  </span>
<% end %>
```

---

### 3.3 드로어 스레드 탭 — 서브 이벤트 목록

**현재**: `_drawer_content.html.erb:342` — `thread_orders` 이미 렌더링 중

**변경**: 쿼리 기준을 `reference_no` → `parent_order_id` 포함으로 통합

**파일**: `app/controllers/orders_controller.rb`

```ruby
def show
  @thread_orders = if @order.reference_no.present?
    # 메인 카드: sub_orders + 동일 reference_no 카드
    Order.where(reference_no: @order.reference_no)
         .or(Order.where(parent_order_id: @order.id))
         .where.not(id: @order.id)
         .order(created_at: :asc)
  elsif @order.parent_order_id.present?
    # 서브 카드에서 접근 시: 메인 카드의 형제들 표시
    Order.where(parent_order_id: @order.parent_order_id)
         .or(Order.where(id: @order.parent_order_id))
         .where.not(id: @order.id)
         .order(created_at: :asc)
  else
    Order.none
  end
end
```

---

### 3.4 Admin 병합 스크립트 — 기존 데이터 정리

**파일**: `lib/tasks/card_merge.rake` (신규)

```ruby
namespace :orders do
  desc "동일 reference_no 중복 카드를 parent_order_id로 병합"
  task merge_duplicates: :environment do
    merged_count = 0

    Order.where.not(reference_no: nil)
         .where(parent_order_id: nil)
         .group(:reference_no)
         .having("COUNT(*) > 1")
         .pluck(:reference_no)
         .each do |ref_no|
           orders = Order.where(reference_no: ref_no)
                         .where(parent_order_id: nil)
                         .order(created_at: :asc)
                         .to_a

           # 가장 오래된 것을 메인으로 지정
           main   = orders.first
           others = orders[1..]

           others.each do |sub|
             sub.update!(parent_order_id: main.id)
             merged_count += 1
             puts "  Merged Order##{sub.id} → parent Order##{main.id} (ref: #{ref_no})"
           end
         end

    puts "병합 완료: #{merged_count}건"
  end
end
```

**실행 방법**:
```bash
# 로컬
bin/rails orders:merge_duplicates

# 프로덕션
kamal app exec --reuse "bin/rails orders:merge_duplicates"
```

---

## 4. 시퀀스 다이어그램

### 신규 이메일 수신 흐름

```
Gmail API
  → EmailSyncJob
    → EmailToOrderService.create_order!
      → ReferenceNumberExtractor.extract(subject, body)
        → ref_no = "6000009460"
      → find_parent_order(ref_no)
        → Order.where(reference_no: ref_no, parent_order_id: nil).first
          → [메인 카드 존재] → parent = Order#512
          → [없음]          → parent = nil
      → [parent 있음]
        Order.create!(parent_order_id: 512, ...)  # 서브 카드
        Activity.create!(order: parent, action: "thread_email_received")
      → [parent 없음]
        Order.create!(parent_order_id: nil, ...)  # 메인 카드
        RfqReplyDraftJob.perform_later
```

### 칸반 카드 렌더링 흐름

```
KanbanController#index
  → Order.where(parent_order_id: nil).where(status: col)
    → 서브 카드 제외된 목록 반환
  → _card.html.erb
    → order.sub_orders.count > 0 → "+N" 배지 표시
```

---

## 5. 구현 체크리스트

### 1단계: DB + 모델 (FR-01)
- [ ] `20260303_add_parent_order_id_to_orders.rb` 마이그레이션 생성
- [ ] `bin/rails db:migrate` 실행
- [ ] `Order` 모델에 `belongs_to :parent_order`, `has_many :sub_orders`, `scope :root_orders` 추가

### 2단계: EmailToOrderService 수정 (FR-03)
- [ ] `check_thread_duplicate` → `find_parent_order`로 교체
- [ ] `create_order!`에 `parent_order_id` 설정 분기 추가
- [ ] `Activity` `thread_email_received` 액션 추가

### 3단계: Rake Task 생성 + 기존 데이터 정리 (FR-06)
- [ ] `lib/tasks/card_merge.rake` 생성
- [ ] 로컬 테스트 후 프로덕션 실행

### 4단계: 칸반 뷰 수정 (FR-04, FR-08)
- [ ] 칸반 쿼리에 `.where(parent_order_id: nil)` 추가
- [ ] 칸반 카드에 서브 카드 수 배지 추가
- [ ] 칸반 컬럼 카운트 쿼리도 동일 필터 적용

### 5단계: 드로어 스레드 탭 (FR-05)
- [ ] `show` 액션 `@thread_orders` 쿼리를 `parent_order_id` 포함으로 업데이트
- [ ] `_drawer_content.html.erb` 스레드 탭 레이블 "관련 메일 스레드" → 유지 (이미 구현)

---

## 6. 테스트 시나리오

| 시나리오 | 기대 결과 |
|---------|---------|
| 동일 ref_no 이메일 3건 수신 | 칸반에 카드 1개, 드로어 스레드 탭에 +2건 표시 |
| 기존 중복 카드 병합 rake 실행 | `parent_order_id` 설정, 칸반 중복 제거 |
| 메인 카드 상태 변경 | 서브 카드 상태 유지 (독립적) |
| 서브 카드 직접 접근 (`/orders/:id`) | 정상 표시, 드로어에 형제 카드 목록 |
| `reference_no` 없는 카드 | 기존과 동일하게 독립 카드로 생성 |

---

## 7. 리스크 및 대응

| 리스크 | 대응 |
|--------|------|
| 칸반 N+1 쿼리 (`sub_orders.count`) | `includes(:sub_orders)` 추가 또는 `counter_cache` 적용 |
| 기존 `kanban-inbox-grouping` 뷰 로직 충돌 | 해당 기능은 이 구현으로 대체, 관련 뷰 코드 제거 |
| Rake 실행 중 데이터 불일치 | 트랜잭션으로 감싸기, 실행 전 백업 권장 |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-03-03 | Initial design |
