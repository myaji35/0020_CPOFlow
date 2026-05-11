# 품목 탭 + 첨부파일 분석 배지 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 발주 드로어에 품목(Items) 탭을 신설하고 첨부파일별 견적 분석 배지를 추가한다 — 사용자가 첨부 PDF의 [분석] 버튼 클릭 시 Claude Sonnet 4.6 vision으로 품목 7컬럼 표를 추출·표시·인라인 편집한다.

**Architecture:** 신규 모델 `AttachmentQuoteAnalysis`(분석 상태/결과) + `OrderQuoteItem`(편집 가능 행). 신규 서비스 `QuoteAttachmentClassifier`(견적성 휴리스틱) + `QuoteItemExtractor`(LLM 호출). 신규 잡 `QuoteAttachmentAnalyzeJob`. 기존 `RfqAuto::*` 자산은 격리. Hotwire Turbo Stream broadcast로 배지/탭 실시간 갱신.

**Tech Stack:** Ruby on Rails 8.1, SQLite3, Active Storage, Solid Queue, Hotwire Turbo, Stimulus, Anthropic Ruby SDK (Sonnet 4.6 vision), TailwindCSS CDN, ImageMagick + poppler(pdftoppm)

**Spec:** `docs/superpowers/specs/2026-05-11-quote-items-tab-design.md`

---

## File Map

### Created
| 경로 | 책임 |
|---|---|
| `db/migrate/<ts>_create_attachment_quote_analyses.rb` | 분석 상태/결과 테이블 마이그레이션 |
| `db/migrate/<ts>_create_order_quote_items.rb` | 품목 행 테이블 마이그레이션 |
| `app/models/attachment_quote_analysis.rb` | 분석 모델 |
| `app/models/order_quote_item.rb` | 품목 행 모델 |
| `app/services/quote_attachment_classifier.rb` | 견적성 휴리스틱 |
| `app/services/quote_item_extractor.rb` | Sonnet 4.6 vision 호출 + JSON 파싱 |
| `app/jobs/quote_attachment_analyze_job.rb` | 비동기 분석 잡 |
| `app/controllers/order_quote_items_controller.rb` | 품목 CRUD (Turbo) |
| `app/controllers/attachment_quote_analyses_controller.rb` | 분석 트리거/재분석 |
| `app/views/orders/_drawer_quote_items.html.erb` | 품목 탭 본문 |
| `app/views/orders/_quote_item_row.html.erb` | 품목 행 partial |
| `app/views/orders/_quote_attachment_badge.html.erb` | 첨부 배지 partial |
| `app/javascript/controllers/quote_item_inline_edit_controller.js` | Stimulus 인라인 편집 |
| `test/models/attachment_quote_analysis_test.rb` | 모델 테스트 |
| `test/models/order_quote_item_test.rb` | 모델 테스트 |
| `test/services/quote_attachment_classifier_test.rb` | 휴리스틱 테스트 |
| `test/services/quote_item_extractor_test.rb` | LLM 호출 테스트 (HTTP stub) |
| `test/controllers/order_quote_items_controller_test.rb` | CRUD 테스트 |
| `test/controllers/attachment_quote_analyses_controller_test.rb` | 트리거 테스트 |

### Modified
| 경로 | 변경 |
|---|---|
| `config/routes.rb` | `resources :orders` 블록에 `quote_items` nested + 최상위 `attachment_quote_analyses` |
| `app/models/order.rb` | `has_many :attachment_quote_analyses, :quote_items` 추가 |
| `app/views/orders/_drawer_content.html.erb` | 7번째 "품목" 탭 추가 + partial render |
| `app/views/orders/_drawer_attachments.html.erb` | 각 첨부 옆 배지 partial render |
| `config/locales/ko.yml`, `config/locales/en.yml` | 품목 탭 i18n 키 추가 |

---

## Phase P1: 데이터 모델 + 라우트 + 빈 품목 탭

### Task 1: 마이그레이션 — `attachment_quote_analyses`

**Files:**
- Create: `db/migrate/<ts>_create_attachment_quote_analyses.rb`
- Test: (마이그레이션은 Task 5에서 모델 테스트로 검증)

- [ ] **Step 1: 마이그레이션 생성**

```bash
bin/rails generate migration CreateAttachmentQuoteAnalyses
```

- [ ] **Step 2: 마이그레이션 작성**

`db/migrate/<ts>_create_attachment_quote_analyses.rb`:
```ruby
class CreateAttachmentQuoteAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :attachment_quote_analyses do |t|
      t.references :order, null: false, foreign_key: true
      t.references :active_storage_attachment, null: false,
                   foreign_key: { to_table: :active_storage_attachments }
      t.string  :status, null: false, default: "pending"
      t.boolean :is_quote_doc, null: false, default: false
      t.text    :items_json
      t.string  :llm_model
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0.0
      t.integer :latency_ms, default: 0
      t.text    :error_message
      t.integer :reanalyzed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :attachment_quote_analyses, :active_storage_attachment_id,
              unique: true, name: "idx_aqa_on_attachment_unique"
    add_index :attachment_quote_analyses, %i[order_id status], name: "idx_aqa_on_order_status"
  end
end
```

- [ ] **Step 3: 마이그레이션 실행**

Run: `bin/rails db:migrate`
Expected: `== CreateAttachmentQuoteAnalyses: migrated`

- [ ] **Step 4: 커밋**

```bash
git add db/migrate/*_create_attachment_quote_analyses.rb db/schema.rb
git commit -m "feat(quote-items): T1 — attachment_quote_analyses 테이블 생성"
```

---

### Task 2: 마이그레이션 — `order_quote_items`

**Files:**
- Create: `db/migrate/<ts>_create_order_quote_items.rb`

- [ ] **Step 1: 마이그레이션 생성**

```bash
bin/rails generate migration CreateOrderQuoteItems
```

- [ ] **Step 2: 마이그레이션 작성**

`db/migrate/<ts>_create_order_quote_items.rb`:
```ruby
class CreateOrderQuoteItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_quote_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :source_attachment, foreign_key: { to_table: :active_storage_attachments }
      t.integer :row_no, null: false, default: 1
      t.string  :item
      t.text    :description
      t.string  :model_part_no
      t.string  :manufacturer_brand
      t.string  :unit
      t.decimal :qty, precision: 12, scale: 3
      t.text    :remarks
      t.boolean :user_edited, null: false, default: false
      t.references :edited_by_user, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :order_quote_items, %i[order_id row_no]
  end
end
```

- [ ] **Step 3: 마이그레이션 실행**

Run: `bin/rails db:migrate`
Expected: `== CreateOrderQuoteItems: migrated`

- [ ] **Step 4: 커밋**

```bash
git add db/migrate/*_create_order_quote_items.rb db/schema.rb
git commit -m "feat(quote-items): T2 — order_quote_items 테이블 생성"
```

---

### Task 3: 모델 — `OrderQuoteItem` (테스트 먼저)

**Files:**
- Create: `app/models/order_quote_item.rb`
- Create: `test/models/order_quote_item_test.rb`

- [ ] **Step 1: 실패하는 테스트 작성**

`test/models/order_quote_item_test.rb`:
```ruby
require "test_helper"

class OrderQuoteItemTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "qi-test@example.com", password: "Pass1234!", name: "QI")
    @order = Order.create!(reference_no: "QI-001", title: "QI 테스트", created_by: @user)
  end

  test "belongs_to order" do
    item = OrderQuoteItem.new(order: @order, row_no: 1, item: "Test")
    assert item.valid?
    assert_equal @order, item.order
  end

  test "row_no required" do
    item = OrderQuoteItem.new(order: @order, item: "X")
    item.row_no = nil
    assert_not item.valid?
  end

  test "user_edited defaults to false" do
    item = OrderQuoteItem.create!(order: @order, row_no: 1, item: "X")
    assert_equal false, item.user_edited
  end
end
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

Run: `bin/rails test test/models/order_quote_item_test.rb -v`
Expected: FAIL with "uninitialized constant OrderQuoteItem"

- [ ] **Step 3: 모델 작성**

`app/models/order_quote_item.rb`:
```ruby
# frozen_string_literal: true

class OrderQuoteItem < ApplicationRecord
  belongs_to :order
  belongs_to :source_attachment, class_name: "ActiveStorage::Attachment", optional: true
  belongs_to :edited_by_user, class_name: "User", optional: true

  validates :row_no, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(:row_no) }
end
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/order_quote_item_test.rb -v`
Expected: 3 runs, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add app/models/order_quote_item.rb test/models/order_quote_item_test.rb
git commit -m "feat(quote-items): T3 — OrderQuoteItem 모델 + 회귀 테스트"
```

---

### Task 4: 모델 — `AttachmentQuoteAnalysis`

**Files:**
- Create: `app/models/attachment_quote_analysis.rb`
- Create: `test/models/attachment_quote_analysis_test.rb`

- [ ] **Step 1: 실패 테스트 작성**

`test/models/attachment_quote_analysis_test.rb`:
```ruby
require "test_helper"

class AttachmentQuoteAnalysisTest < ActiveSupport::TestCase
  setup do
    @user  = User.create!(email: "aqa-test@example.com", password: "Pass1234!", name: "AQA")
    @order = Order.create!(reference_no: "AQA-001", title: "AQA 테스트", created_by: @user)
    @order.attachments.attach(
      io: StringIO.new("dummy"), filename: "RFQ-001.pdf", content_type: "application/pdf"
    )
    @attachment = @order.attachments.first
  end

  test "STATUSES whitelist" do
    assert_equal %w[pending running completed failed not_quote], AttachmentQuoteAnalysis::STATUSES
  end

  test "creates with order + attachment" do
    aqa = AttachmentQuoteAnalysis.create!(order: @order, active_storage_attachment_id: @attachment.id)
    assert_equal "pending", aqa.status
    assert_equal 0, aqa.reanalyzed_count
    assert_equal false, aqa.is_quote_doc
  end

  test "items returns parsed array" do
    aqa = AttachmentQuoteAnalysis.create!(
      order: @order, active_storage_attachment_id: @attachment.id,
      items_json: '[{"item":"X"}]'
    )
    assert_equal [{ "item" => "X" }], aqa.items
  end

  test "items returns [] when items_json blank or invalid" do
    aqa = AttachmentQuoteAnalysis.new(order: @order, active_storage_attachment_id: @attachment.id)
    assert_equal [], aqa.items
    aqa.items_json = "{not json"
    assert_equal [], aqa.items
  end

  test "unique attachment_id" do
    AttachmentQuoteAnalysis.create!(order: @order, active_storage_attachment_id: @attachment.id)
    dup = AttachmentQuoteAnalysis.new(order: @order, active_storage_attachment_id: @attachment.id)
    assert_not dup.valid?
  end
end
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

Run: `bin/rails test test/models/attachment_quote_analysis_test.rb -v`
Expected: FAIL with "uninitialized constant AttachmentQuoteAnalysis"

- [ ] **Step 3: 모델 작성**

`app/models/attachment_quote_analysis.rb`:
```ruby
# frozen_string_literal: true

class AttachmentQuoteAnalysis < ApplicationRecord
  STATUSES = %w[pending running completed failed not_quote].freeze

  belongs_to :order
  belongs_to :active_storage_attachment, class_name: "ActiveStorage::Attachment"

  validates :status, inclusion: { in: STATUSES }
  validates :active_storage_attachment_id, uniqueness: true

  scope :recent, -> { order(updated_at: :desc) }

  def items
    return [] if items_json.blank?
    parsed = JSON.parse(items_json)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bin/rails test test/models/attachment_quote_analysis_test.rb -v`
Expected: 5 runs, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add app/models/attachment_quote_analysis.rb test/models/attachment_quote_analysis_test.rb
git commit -m "feat(quote-items): T4 — AttachmentQuoteAnalysis 모델 + 회귀 테스트"
```

---

### Task 5: `Order` 모델에 has_many 추가

**Files:**
- Modify: `app/models/order.rb`
- Modify: `test/models/order_test.rb`

- [ ] **Step 1: Order 모델에 관계 추가**

`app/models/order.rb`의 `has_many_attached :attachments` 줄 직후에 추가:
```ruby
  has_many :attachment_quote_analyses, dependent: :destroy
  has_many :quote_items, class_name: "OrderQuoteItem", dependent: :destroy
```

- [ ] **Step 2: 테스트 추가**

`test/models/order_test.rb` 끝에 추가:
```ruby
  test "has_many :attachment_quote_analyses" do
    order = Order.create!(reference_no: "OQA-001", title: "T", created_by: User.first || User.create!(email: "x@x.com", password: "Pass1234!", name: "X"))
    assert_respond_to order, :attachment_quote_analyses
    assert_respond_to order, :quote_items
  end
```

- [ ] **Step 3: 테스트 실행**

Run: `bin/rails test test/models/order_test.rb -v`
Expected: PASS (신규 테스트 1개 + 기존 테스트 모두)

- [ ] **Step 4: 커밋**

```bash
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat(quote-items): T5 — Order has_many quote_items/analyses"
```

---

### Task 6: 라우트 추가

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: 라우트 추가**

`config/routes.rb`에서 첫 번째 `resources :orders do` 블록 안 (`resources :tasks, ...` 옆)에 추가:
```ruby
    resources :quote_items, only: %i[index create update destroy], controller: "order_quote_items"
```

그리고 파일 끝 다른 최상위 라우트와 같은 들여쓰기 위치에 추가:
```ruby
  resources :attachment_quote_analyses, only: %i[create] do
    member { post :reanalyze }
  end
```

- [ ] **Step 2: 라우트 검증**

Run: `bin/rails routes -g quote_items`
Expected: 4개 라인 출력 (index/create/update/destroy)

Run: `bin/rails routes -g attachment_quote_analyses`
Expected: 2개 라인 (create, reanalyze)

- [ ] **Step 3: 커밋**

```bash
git add config/routes.rb
git commit -m "feat(quote-items): T6 — quote_items + attachment_quote_analyses 라우트"
```

---

### Task 7: 빈 품목 탭 + 드로어 탭바 7번째 추가

**Files:**
- Create: `app/views/orders/_drawer_quote_items.html.erb`
- Modify: `app/views/orders/_drawer_content.html.erb`
- Modify: `config/locales/ko.yml`, `config/locales/en.yml`

- [ ] **Step 1: i18n 키 추가**

`config/locales/ko.yml`의 `orders.drawer` 섹션에 추가:
```yaml
        tab_quote_items: "품목"
```

`config/locales/en.yml` 동일 위치:
```yaml
        tab_quote_items: "Items"
```

- [ ] **Step 2: 빈 품목 탭 partial 작성**

`app/views/orders/_drawer_quote_items.html.erb`:
```erb
<% initial_render = local_assigns.fetch(:initial_render, true) %>
<div id="drawer-panel-<%= order.id %>-quote_items"
     class="p-6<%= ' hidden' if initial_render %>"
     data-controller="quote-item-inline-edit">
  <turbo-frame id="quote-items-frame-<%= order.id %>"
               src="<%= order_quote_items_path(order) %>"
               loading="lazy">
    <div class="text-sm text-gray-500 py-12 text-center">
      품목 데이터를 불러오는 중...
    </div>
  </turbo-frame>
</div>
```

- [ ] **Step 3: 드로어 탭바에 7번째 탭 추가**

`app/views/orders/_drawer_content.html.erb`의 16번째 줄 근처에서 `is_purchase` 분기 안의 tabs 배열에 `quote_items` 추가:

기존:
```erb
    <% tabs = if is_purchase
      [['detail', t('orders.drawer.tab_detail')], ['tasks', t('orders.drawer.tab_tasks')], ['comments', t('orders.drawer.tab_comments')], ['attachments', t('orders.drawer.tab_attachments')], ['history', t('orders.drawer.tab_history')], ['flow', t('orders.drawer.tab_flow')]]
```

변경:
```erb
    <% tabs = if is_purchase
      [['detail', t('orders.drawer.tab_detail')], ['tasks', t('orders.drawer.tab_tasks')], ['comments', t('orders.drawer.tab_comments')], ['attachments', t('orders.drawer.tab_attachments')], ['quote_items', t('orders.drawer.tab_quote_items')], ['history', t('orders.drawer.tab_history')], ['flow', t('orders.drawer.tab_flow')]]
```

그리고 첨부파일 partial 렌더 직후 (`<%# 탭 패널 5: 히스토리 %>` 직전) 새 패널 추가:
```erb
  <%# 탭 패널: 품목 %>
  <%= render partial: "orders/drawer_quote_items", locals: { order: order, initial_render: true } %>
```

- [ ] **Step 4: 컨트롤러 + 빈 응답 작성 (Task 9 본 구현 전 임시)**

`app/controllers/order_quote_items_controller.rb`:
```ruby
# frozen_string_literal: true

class OrderQuoteItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order

  def index
    @items = @order.quote_items.ordered
    @sources = AttachmentQuoteAnalysis.where(order_id: @order.id, status: "completed").includes(:active_storage_attachment)
    render partial: "orders/quote_items_frame", locals: { order: @order, items: @items, sources: @sources }
  end

  private

  def set_order
    @order = Order.find(params[:order_id])
  end
end
```

`app/views/orders/_quote_items_frame.html.erb` (신규):
```erb
<turbo-frame id="quote-items-frame-<%= order.id %>">
  <% if items.any? %>
    <div class="text-sm text-gray-700">품목 <%= items.size %>건 (P3에서 표 렌더)</div>
  <% else %>
    <div class="py-12 text-center">
      <div class="text-3xl mb-2">📋</div>
      <div class="text-sm text-gray-700 mb-1">품목이 아직 없습니다</div>
      <div class="text-xs text-gray-500">견적성 첨부파일에서 [분석] 버튼을 눌러 추출하세요.</div>
    </div>
  <% end %>
</turbo-frame>
```

- [ ] **Step 5: 빈 상태 동작 확인 (수동)**

Run: `bin/rails server -p 3000 -d` (이미 띄워져 있으면 skip)
Run: `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/orders/1/quote_items`
Expected: `302` (인증 필요) — 정상

Run: `bin/rails test test/models/ -v`
Expected: 모든 모델 테스트 PASS

- [ ] **Step 6: 커밋**

```bash
git add app/views/orders/_drawer_quote_items.html.erb \
        app/views/orders/_quote_items_frame.html.erb \
        app/views/orders/_drawer_content.html.erb \
        app/controllers/order_quote_items_controller.rb \
        config/locales/ko.yml config/locales/en.yml
git commit -m "feat(quote-items): T7 — 품목 탭 + 빈 상태 + index 컨트롤러"
```

---

## Phase P2: 분석 파이프라인 (Classifier + Job + Extractor + 배지)

### Task 8: `QuoteAttachmentClassifier` 서비스

**Files:**
- Create: `app/services/quote_attachment_classifier.rb`
- Create: `test/services/quote_attachment_classifier_test.rb`

- [ ] **Step 1: 실패 테스트 작성**

`test/services/quote_attachment_classifier_test.rb`:
```ruby
require "test_helper"

class QuoteAttachmentClassifierTest < ActiveSupport::TestCase
  def attach(filename, content_type)
    user  = User.first || User.create!(email: "qac@x.com", password: "Pass1234!", name: "QAC")
    order = Order.create!(reference_no: "QAC-#{rand(9999)}", title: "T", created_by: user)
    order.attachments.attach(io: StringIO.new("d"), filename: filename, content_type: content_type)
    order.attachments.first
  end

  test "RFQ keyword → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(attach("RFQ-100.pdf", "application/pdf"))
  end

  test "MULKIYA keyword → quote_candidate" do
    assert_equal :quote_candidate, QuoteAttachmentClassifier.call(attach("MULKIYA 29758.pdf", "application/pdf"))
  end

  test "INVOICE keyword → not_quote" do
    assert_equal :not_quote, QuoteAttachmentClassifier.call(attach("Invoice-2024.pdf", "application/pdf"))
  end

  test "audio MIME → not_quote" do
    assert_equal :not_quote, QuoteAttachmentClassifier.call(attach("voice.mp3", "audio/mpeg"))
  end

  test "PDF without keyword → ambiguous" do
    assert_equal :ambiguous, QuoteAttachmentClassifier.call(attach("doc-12.pdf", "application/pdf"))
  end
end
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

Run: `bin/rails test test/services/quote_attachment_classifier_test.rb -v`
Expected: FAIL with "uninitialized constant QuoteAttachmentClassifier"

- [ ] **Step 3: 서비스 작성**

`app/services/quote_attachment_classifier.rb`:
```ruby
# frozen_string_literal: true

class QuoteAttachmentClassifier
  POSITIVE_KEYWORDS = %w[RFQ QUO QUOTE QUOTATION INQUIRY BOQ MULKIYA MTR].freeze
  NEGATIVE_KEYWORDS = %w[INVOICE RECEIPT CONTRACT NDA LICENSE AGREEMENT].freeze

  POSITIVE_MIMES = %w[
    application/pdf image/png image/jpeg
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ].freeze

  NEGATIVE_MIME_PREFIXES = %w[audio/ video/].freeze
  NEGATIVE_MIMES = %w[text/calendar application/zip].freeze

  def self.call(attachment)
    new(attachment).call
  end

  def initialize(attachment)
    @attachment = attachment
  end

  def call
    return :not_quote if negative_mime?
    return :not_quote if negative_keyword?
    return :quote_candidate if positive_keyword?
    return :ambiguous if positive_mime?
    :not_quote
  end

  private

  def filename
    @filename ||= @attachment.filename.to_s.upcase
  end

  def mime
    @mime ||= @attachment.content_type.to_s.downcase
  end

  def positive_keyword?
    POSITIVE_KEYWORDS.any? { |kw| filename.include?(kw) }
  end

  def negative_keyword?
    NEGATIVE_KEYWORDS.any? { |kw| filename.include?(kw) }
  end

  def positive_mime?
    POSITIVE_MIMES.include?(mime)
  end

  def negative_mime?
    NEGATIVE_MIMES.include?(mime) || NEGATIVE_MIME_PREFIXES.any? { |p| mime.start_with?(p) }
  end
end
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bin/rails test test/services/quote_attachment_classifier_test.rb -v`
Expected: 5 runs, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add app/services/quote_attachment_classifier.rb test/services/quote_attachment_classifier_test.rb
git commit -m "feat(quote-items): T8 — QuoteAttachmentClassifier (양성/음성 키워드+MIME)"
```

---

### Task 9: `QuoteItemExtractor` 서비스 (PDF→이미지→Sonnet)

**Files:**
- Create: `app/services/quote_item_extractor.rb`
- Create: `test/services/quote_item_extractor_test.rb`

- [ ] **Step 1: 실패 테스트 작성 (HTTP stub)**

`test/services/quote_item_extractor_test.rb`:
```ruby
require "test_helper"

class QuoteItemExtractorTest < ActiveSupport::TestCase
  setup do
    @user  = User.first || User.create!(email: "qie@x.com", password: "Pass1234!", name: "QIE")
    @order = Order.create!(reference_no: "QIE-#{rand(9999)}", title: "T", created_by: @user)
    pdf_bytes = File.binread(Rails.root.join("test/fixtures/files/sample.pdf"))
    @order.attachments.attach(io: StringIO.new(pdf_bytes), filename: "RFQ.pdf", content_type: "application/pdf")
    @attachment = @order.attachments.first
  end

  test "raises AnthropicCreditError on 401" do
    QuoteItemExtractor.any_instance.stubs(:render_pages).returns(["base64data"])
    QuoteItemExtractor.any_instance.stubs(:call_anthropic).raises(QuoteItemExtractor::AnthropicCreditError, "insufficient")

    assert_raises(QuoteItemExtractor::AnthropicCreditError) do
      QuoteItemExtractor.new(@attachment).call
    end
  end

  test "returns items + cost on success" do
    QuoteItemExtractor.any_instance.stubs(:render_pages).returns(["b64"])
    QuoteItemExtractor.any_instance.stubs(:call_anthropic).returns([100, 50, [{ "item" => "SPILL TRAY" }]])

    result = QuoteItemExtractor.new(@attachment).call
    assert_equal 1, result[:items].size
    assert_equal "SPILL TRAY", result[:items].first["item"]
    assert result[:cost_usd] > 0
    assert_equal "claude-sonnet-4-6", result[:llm_model]
  end

  test "returns empty items when LLM returns none" do
    QuoteItemExtractor.any_instance.stubs(:render_pages).returns(["b64"])
    QuoteItemExtractor.any_instance.stubs(:call_anthropic).returns([100, 10, []])

    result = QuoteItemExtractor.new(@attachment).call
    assert_equal [], result[:items]
  end
end
```

- [ ] **Step 2: 픽스처 PDF 준비**

```bash
mkdir -p test/fixtures/files
[ -f test/fixtures/files/sample.pdf ] || \
  printf "%%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n%%EOF\n" > test/fixtures/files/sample.pdf
```

- [ ] **Step 3: 테스트 실행 (실패 확인)**

Run: `bin/rails test test/services/quote_item_extractor_test.rb -v`
Expected: FAIL with "uninitialized constant QuoteItemExtractor"

- [ ] **Step 4: 서비스 작성**

`app/services/quote_item_extractor.rb`:
```ruby
# frozen_string_literal: true

require "base64"
require "open3"
require "tmpdir"

class QuoteItemExtractor
  MODEL = ENV.fetch("QUOTE_EXTRACTOR_MODEL", "claude-sonnet-4-6")
  DEFAULT_PAGES_CAP = 5
  INPUT_PER_MTOK   = 3.00
  OUTPUT_PER_MTOK  = 15.00

  class AnthropicCreditError < StandardError; end
  class ExtractionError < StandardError; end

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You extract procurement RFQ line items from images of quotation request documents.
    Return ONLY a JSON object with this exact shape:
    {
      "items": [
        {
          "item": "...",
          "description": "...",
          "model_part_no": "...",
          "manufacturer_brand": "...",
          "unit": "...",
          "qty": "...",
          "remarks": "..."
        }
      ]
    }
    Rules:
    - "item" is required (item/product name, original language preserved).
    - "description" preserves multi-line specs (DIMENSIONS / MATERIAL / CAPACITY / COLOR / etc).
    - "model_part_no": model number or part/SKU (e.g. "5004-BK").
    - "manufacturer_brand": OEM/maker or brand (e.g. "ENPAC").
    - "unit": EA / KG / SET / M / etc.
    - "qty": numeric or numeric-with-unit string.
    - "remarks": free-form notes (delivery condition, packaging, QC).
    - If document is NOT a procurement RFQ/quotation request, return {"items": []}.
    - Output JSON only, no commentary.
  PROMPT

  def initialize(attachment, pages_cap: DEFAULT_PAGES_CAP)
    @attachment = attachment
    @pages_cap = pages_cap
  end

  def call
    images = render_pages
    return empty_result(reason: "no_images") if images.empty?

    input_tokens, output_tokens, items = call_anthropic(images)
    cost = (input_tokens.to_f * INPUT_PER_MTOK / 1_000_000) +
           (output_tokens.to_f * OUTPUT_PER_MTOK / 1_000_000)

    { items: items, cost_usd: cost.round(4), llm_model: MODEL,
      page_count: images.size, latency_ms: 0 }
  end

  private

  def empty_result(reason:)
    { items: [], cost_usd: 0.0, llm_model: MODEL, page_count: 0, reason: reason, latency_ms: 0 }
  end

  def render_pages
    return [] unless @attachment.blob.present?
    case @attachment.content_type
    when "application/pdf"           then render_pdf_pages
    when /^image\//                  then [base64_image(@attachment.download)]
    else []
    end
  end

  def render_pdf_pages
    Dir.mktmpdir do |dir|
      pdf_path = File.join(dir, "in.pdf")
      File.binwrite(pdf_path, @attachment.download)
      out_prefix = File.join(dir, "page")
      stdout, stderr, status = Open3.capture3(
        "pdftoppm", "-png", "-r", "150", "-f", "1", "-l", @pages_cap.to_s, pdf_path, out_prefix
      )
      raise ExtractionError, "pdftoppm failed: #{stderr}" unless status.success?
      Dir.glob("#{out_prefix}-*.png").sort.map { |p| base64_image(File.binread(p)) }
    end
  end

  def base64_image(bytes)
    Base64.strict_encode64(bytes)
  end

  def call_anthropic(images)
    api_key = AppSetting.get("anthropic_api_key").presence ||
              Rails.application.credentials.dig(:anthropic, :api_key)
    raise AnthropicCreditError, "API key not configured" if api_key.blank?

    client = Anthropic::Client.new(api_key: api_key)
    content = images.map { |b64| { type: "image", source: { type: "base64", media_type: "image/png", data: b64 } } }
    content << { type: "text", text: "Extract items as JSON. Return {\"items\":[...]}" }

    resp = client.messages(
      parameters: {
        model: MODEL, max_tokens: 4096,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: content }]
      }
    )
    text = resp.dig("content", 0, "text").to_s
    parsed = JSON.parse(text.match(/\{.*\}/m).to_s)
    items = Array(parsed["items"])
    [resp.dig("usage", "input_tokens").to_i, resp.dig("usage", "output_tokens").to_i, items]
  rescue Anthropic::Errors::APIError => e
    raise AnthropicCreditError, e.message if e.message.include?("insufficient") || e.message.include?("401")
    raise ExtractionError, "LLM call failed: #{e.message}"
  rescue JSON::ParserError => e
    raise ExtractionError, "Invalid JSON: #{e.message}"
  end
end
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `bin/rails test test/services/quote_item_extractor_test.rb -v`
Expected: 3 runs, 0 failures

- [ ] **Step 6: 커밋**

```bash
git add app/services/quote_item_extractor.rb test/services/quote_item_extractor_test.rb test/fixtures/files/sample.pdf
git commit -m "feat(quote-items): T9 — QuoteItemExtractor (Sonnet 4.6 vision)"
```

---

### Task 10: `QuoteAttachmentAnalyzeJob` 잡 + 시드 로직

**Files:**
- Create: `app/jobs/quote_attachment_analyze_job.rb`
- Create: `test/jobs/quote_attachment_analyze_job_test.rb`

- [ ] **Step 1: 실패 테스트 작성**

`test/jobs/quote_attachment_analyze_job_test.rb`:
```ruby
require "test_helper"

class QuoteAttachmentAnalyzeJobTest < ActiveJob::TestCase
  setup do
    @user  = User.first || User.create!(email: "jb@x.com", password: "Pass1234!", name: "JB")
    @order = Order.create!(reference_no: "JB-#{rand(9999)}", title: "T", created_by: @user)
    @order.attachments.attach(io: StringIO.new("d"), filename: "RFQ.pdf", content_type: "application/pdf")
    @aqa = AttachmentQuoteAnalysis.create!(order: @order, active_storage_attachment_id: @order.attachments.first.id)
  end

  test "marks completed and seeds items on success" do
    QuoteItemExtractor.any_instance.stubs(:call).returns(
      items: [{ "item" => "SPILL TRAY", "description" => "129x119", "model_part_no" => "5004-BK",
                "manufacturer_brand" => "ENPAC", "unit" => "EA", "qty" => "16", "remarks" => "" }],
      cost_usd: 0.02, llm_model: "claude-sonnet-4-6", page_count: 1, latency_ms: 100
    )

    QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)

    @aqa.reload
    assert_equal "completed", @aqa.status
    assert_equal true, @aqa.is_quote_doc
    assert_equal 1, @order.quote_items.count
    assert_equal "SPILL TRAY", @order.quote_items.first.item
  end

  test "marks failed on AnthropicCreditError" do
    QuoteItemExtractor.any_instance.stubs(:call).raises(QuoteItemExtractor::AnthropicCreditError, "insufficient")
    QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    @aqa.reload
    assert_equal "failed", @aqa.status
    assert_match(/insufficient/, @aqa.error_message)
  end

  test "completed but is_quote_doc=false on empty items" do
    QuoteItemExtractor.any_instance.stubs(:call).returns(items: [], cost_usd: 0.01, llm_model: "claude-sonnet-4-6", page_count: 1, latency_ms: 50)
    QuoteAttachmentAnalyzeJob.perform_now(@aqa.id)
    @aqa.reload
    assert_equal "completed", @aqa.status
    assert_equal false, @aqa.is_quote_doc
    assert_equal 0, @order.quote_items.count
  end
end
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

Run: `bin/rails test test/jobs/quote_attachment_analyze_job_test.rb -v`
Expected: FAIL with "uninitialized constant QuoteAttachmentAnalyzeJob"

- [ ] **Step 3: 잡 작성**

`app/jobs/quote_attachment_analyze_job.rb`:
```ruby
# frozen_string_literal: true

class QuoteAttachmentAnalyzeJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    aqa = AttachmentQuoteAnalysis.find(analysis_id)
    aqa.update!(status: "running", started_at: Time.current)
    broadcast_badge(aqa)

    result = QuoteItemExtractor.new(aqa.active_storage_attachment).call

    aqa.update!(
      status: "completed",
      is_quote_doc: result[:items].any?,
      items_json: result[:items].to_json,
      llm_model: result[:llm_model],
      cost_usd: result[:cost_usd],
      latency_ms: result[:latency_ms],
      completed_at: Time.current
    )
    seed_items(aqa, result[:items]) if result[:items].any?
    broadcast_badge(aqa)
    broadcast_items_frame(aqa.order)
  rescue QuoteItemExtractor::AnthropicCreditError, QuoteItemExtractor::ExtractionError, StandardError => e
    aqa.update!(status: "failed", error_message: "#{e.class}: #{e.message}", completed_at: Time.current)
    broadcast_badge(aqa)
  end

  private

  def seed_items(aqa, items)
    next_row = (aqa.order.quote_items.maximum(:row_no) || 0) + 1
    items.each_with_index do |raw, idx|
      OrderQuoteItem.create!(
        order: aqa.order,
        source_attachment_id: aqa.active_storage_attachment_id,
        row_no: next_row + idx,
        item: raw["item"].to_s.presence,
        description: raw["description"],
        model_part_no: raw["model_part_no"],
        manufacturer_brand: raw["manufacturer_brand"],
        unit: raw["unit"],
        qty: parse_qty(raw["qty"]),
        remarks: raw["remarks"]
      )
    end
  end

  def parse_qty(raw)
    return nil if raw.blank?
    BigDecimal(raw.to_s.scan(/[\d.]+/).first || "0")
  rescue ArgumentError
    nil
  end

  def broadcast_badge(aqa)
    Turbo::StreamsChannel.broadcast_replace_to(
      "order-#{aqa.order_id}",
      target: "quote-attachment-badge-#{aqa.active_storage_attachment_id}",
      partial: "orders/quote_attachment_badge",
      locals: { order: aqa.order, attachment: aqa.active_storage_attachment, aqa: aqa }
    )
  end

  def broadcast_items_frame(order)
    Turbo::StreamsChannel.broadcast_replace_to(
      "order-#{order.id}",
      target: "quote-items-frame-#{order.id}",
      partial: "orders/quote_items_frame",
      locals: {
        order: order,
        items: order.quote_items.ordered,
        sources: AttachmentQuoteAnalysis.where(order_id: order.id, status: "completed")
      }
    )
  end
end
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bin/rails test test/jobs/quote_attachment_analyze_job_test.rb -v`
Expected: 3 runs, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add app/jobs/quote_attachment_analyze_job.rb test/jobs/quote_attachment_analyze_job_test.rb
git commit -m "feat(quote-items): T10 — AnalyzeJob (시드+broadcast+failure)"
```

---

### Task 11: `AttachmentQuoteAnalysesController` + 첨부 배지

**Files:**
- Create: `app/controllers/attachment_quote_analyses_controller.rb`
- Create: `app/views/orders/_quote_attachment_badge.html.erb`
- Create: `test/controllers/attachment_quote_analyses_controller_test.rb`
- Modify: `app/views/orders/_drawer_attachments.html.erb` (배지 partial render)

- [ ] **Step 1: 실패 테스트 작성**

`test/controllers/attachment_quote_analyses_controller_test.rb`:
```ruby
require "test_helper"

class AttachmentQuoteAnalysesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user  = User.create!(email: "ctrl@x.com", password: "Pass1234!", name: "C", role: "member")
    @order = Order.create!(reference_no: "CT-1", title: "T", created_by: @user)
    @order.attachments.attach(io: StringIO.new("d"), filename: "RFQ.pdf", content_type: "application/pdf")
    @attachment = @order.attachments.first
    sign_in @user
  end

  test "create enqueues job + creates AQA" do
    assert_enqueued_with(job: QuoteAttachmentAnalyzeJob) do
      post attachment_quote_analyses_path, params: { attachment_id: @attachment.id }, as: :turbo_stream
    end
    assert_response :success
    assert AttachmentQuoteAnalysis.exists?(active_storage_attachment_id: @attachment.id)
  end

  test "reanalyze increments reanalyzed_count" do
    aqa = AttachmentQuoteAnalysis.create!(order: @order, active_storage_attachment_id: @attachment.id, status: "completed")
    assert_enqueued_with(job: QuoteAttachmentAnalyzeJob) do
      post reanalyze_attachment_quote_analysis_path(aqa), as: :turbo_stream
    end
    assert_equal 1, aqa.reload.reanalyzed_count
  end
end
```

- [ ] **Step 2: 컨트롤러 작성**

`app/controllers/attachment_quote_analyses_controller.rb`:
```ruby
# frozen_string_literal: true

class AttachmentQuoteAnalysesController < ApplicationController
  before_action :authenticate_user!

  def create
    attachment = ActiveStorage::Attachment.find(params[:attachment_id])
    order = attachment.record
    authorize_member!(order)

    aqa = AttachmentQuoteAnalysis.find_or_initialize_by(active_storage_attachment_id: attachment.id)
    aqa.assign_attributes(order: order, status: "pending")
    aqa.save!

    QuoteAttachmentAnalyzeJob.perform_later(aqa.id)

    render turbo_stream: turbo_stream.replace(
      "quote-attachment-badge-#{attachment.id}",
      partial: "orders/quote_attachment_badge",
      locals: { order: order, attachment: attachment, aqa: aqa }
    )
  end

  def reanalyze
    aqa = AttachmentQuoteAnalysis.find(params[:id])
    authorize_member!(aqa.order)
    aqa.increment!(:reanalyzed_count)
    aqa.update!(status: "pending")
    QuoteAttachmentAnalyzeJob.perform_later(aqa.id)

    render turbo_stream: turbo_stream.replace(
      "quote-attachment-badge-#{aqa.active_storage_attachment_id}",
      partial: "orders/quote_attachment_badge",
      locals: { order: aqa.order, attachment: aqa.active_storage_attachment, aqa: aqa }
    )
  end

  private

  def authorize_member!(order)
    head :forbidden unless current_user.role.in?(%w[member manager admin])
  end
end
```

- [ ] **Step 3: 배지 partial 작성**

`app/views/orders/_quote_attachment_badge.html.erb`:
```erb
<% kind = QuoteAttachmentClassifier.call(attachment) %>
<% status = aqa&.status %>
<span id="quote-attachment-badge-<%= attachment.id %>" class="inline-flex items-center">
  <% if status == "running" || status == "pending" %>
    <span class="px-2 py-0.5 rounded-md text-[11px] bg-gray-100 text-gray-700 animate-pulse">⏳ 견적 분석중...</span>
  <% elsif status == "completed" && aqa.is_quote_doc %>
    <button type="button"
            onclick="switchDrawerTab(<%= order.id %>, 'quote_items')"
            class="px-2 py-0.5 rounded-md text-[11px] bg-[#00A1E0]/10 text-[#00A1E0] hover:bg-[#00A1E0]/20 cursor-pointer">
      ✅ 견적분석
    </button>
  <% elsif status == "completed" && !aqa.is_quote_doc %>
    <span class="px-2 py-0.5 rounded-md text-[11px] bg-gray-100 text-gray-500">🚫 견적 아님</span>
  <% elsif status == "failed" %>
    <% credit_issue = aqa.error_message.to_s.match?(/insufficient|401|credit/i) %>
    <%= form_with url: reanalyze_attachment_quote_analysis_path(aqa), method: :post, data: { turbo_stream: true }, class: "inline" do %>
      <button type="submit" class="px-2 py-0.5 rounded-md text-[11px] bg-red-50 text-red-700 hover:bg-red-100 cursor-pointer">
        <%= credit_issue ? "💳 잔액 부족" : "⚠️ 재분석" %>
      </button>
    <% end %>
  <% elsif kind == :quote_candidate %>
    <%= form_with url: attachment_quote_analyses_path, data: { turbo_stream: true }, class: "inline" do |f| %>
      <%= f.hidden_field :attachment_id, value: attachment.id %>
      <button type="submit" class="px-2 py-0.5 rounded-md text-[11px] bg-[#00A1E0]/10 text-[#00A1E0] hover:bg-[#00A1E0]/20 cursor-pointer">🔍 분석</button>
    <% end %>
  <% end %>
</span>
```

- [ ] **Step 4: 첨부 탭에 배지 삽입**

`app/views/orders/_drawer_attachments.html.erb`에서 첨부 항목의 액션 버튼들(`<%= ... %>` `[👁] [⬇] [🗑]` 영역) 옆에 배지 partial을 추가:

대상 부분 찾기 — `active_storage_attachments.each do |att|` 루프 안 (ERB 검색 키워드: `att.filename` 또는 `purge`):
```erb
<%= render partial: "orders/quote_attachment_badge",
            locals: { order: order, attachment: att,
                      aqa: AttachmentQuoteAnalysis.find_by(active_storage_attachment_id: att.id) } %>
```

(주의: 이 partial 호출은 첨부 박스 안 우측 액션 버튼 영역 옆에 위치. N+1 우려 있으나 MVP 허용.)

- [ ] **Step 5: 테스트 통과 확인**

Run: `bin/rails test test/controllers/attachment_quote_analyses_controller_test.rb -v`
Expected: 2 runs, 0 failures

Run: `bin/rails test`
Expected: 전체 회귀 테스트 PASS

- [ ] **Step 6: 커밋**

```bash
git add app/controllers/attachment_quote_analyses_controller.rb \
        app/views/orders/_quote_attachment_badge.html.erb \
        app/views/orders/_drawer_attachments.html.erb \
        test/controllers/attachment_quote_analyses_controller_test.rb
git commit -m "feat(quote-items): T11 — 분석 트리거 컨트롤러 + 첨부 배지"
```

---

## Phase P3: 품목 탭 7컬럼 표 + 헤더

### Task 12: 품목 표 partial — 7컬럼 + 출처 헤더

**Files:**
- Modify: `app/views/orders/_quote_items_frame.html.erb` (Task 7에서 만든 빈 frame을 본 구현으로 교체)
- Create: `app/views/orders/_quote_item_row.html.erb`

- [ ] **Step 1: 품목 행 partial 작성**

`app/views/orders/_quote_item_row.html.erb`:
```erb
<tr id="quote-item-<%= item.id %>" class="border-b border-gray-100">
  <td class="px-2 py-2 text-xs text-gray-500 text-center w-12"><%= item.row_no %></td>
  <td class="px-2 py-2 text-sm" data-field="item" data-item-id="<%= item.id %>">
    <span class="quote-cell-text"><%= item.item %></span>
    <% if item.user_edited %><span class="ml-1 text-[10px] text-[#00A1E0]">•</span><% end %>
  </td>
  <td class="px-2 py-2 text-xs whitespace-pre-line" data-field="description" data-item-id="<%= item.id %>" style="max-width: 280px;">
    <%= item.description %>
  </td>
  <td class="px-2 py-2 text-xs" data-field="model_part_no" data-item-id="<%= item.id %>"><%= item.model_part_no %></td>
  <td class="px-2 py-2 text-xs" data-field="manufacturer_brand" data-item-id="<%= item.id %>"><%= item.manufacturer_brand %></td>
  <td class="px-2 py-2 text-xs text-center w-16" data-field="unit" data-item-id="<%= item.id %>"><%= item.unit %></td>
  <td class="px-2 py-2 text-xs text-right w-20" data-field="qty" data-item-id="<%= item.id %>"><%= item.qty %></td>
  <td class="px-2 py-2 text-xs" data-field="remarks" data-item-id="<%= item.id %>"><%= item.remarks %></td>
  <td class="px-2 py-2 text-xs w-8">
    <%= button_to order_quote_item_path(item.order_id, item),
        method: :delete, form: { data: { turbo_stream: true } },
        class: "text-gray-400 hover:text-red-500" do %>🗑<% end %>
  </td>
</tr>
```

- [ ] **Step 2: frame partial 본 구현으로 교체**

`app/views/orders/_quote_items_frame.html.erb`:
```erb
<turbo-frame id="quote-items-frame-<%= order.id %>">
  <% if items.any? %>
    <div class="mb-3 text-xs text-gray-600">
      품목 <strong><%= items.size %></strong>건
      <% if sources.any? %>
        · 출처:
        <% sources.each_with_index do |s, i| %>
          <span><%= s.active_storage_attachment.filename %></span><%= "," if i < sources.size - 1 %>
        <% end %>
      <% end %>
    </div>

    <div class="overflow-x-auto border border-gray-200 rounded-lg">
      <table class="min-w-full">
        <thead class="bg-gray-50 text-[11px] text-gray-600">
          <tr>
            <th class="px-2 py-2 w-12">No</th>
            <th class="px-2 py-2 text-left">Item</th>
            <th class="px-2 py-2 text-left">Description</th>
            <th class="px-2 py-2 text-left">Model / Part No</th>
            <th class="px-2 py-2 text-left">Manufacturer / Brand</th>
            <th class="px-2 py-2 w-16">Unit</th>
            <th class="px-2 py-2 w-20 text-right">Qty</th>
            <th class="px-2 py-2 text-left">Remarks</th>
            <th class="px-2 py-2 w-8"></th>
          </tr>
        </thead>
        <tbody id="quote-items-tbody-<%= order.id %>">
          <% items.each do |item| %>
            <%= render partial: "orders/quote_item_row", locals: { item: item } %>
          <% end %>
        </tbody>
      </table>
    </div>

    <div class="mt-3 flex items-center gap-2">
      <%= form_with url: order_quote_items_path(order), data: { turbo_stream: true }, class: "inline" do |f| %>
        <button type="submit" class="px-3 py-1.5 text-xs bg-gray-100 hover:bg-gray-200 rounded-md cursor-pointer">+ 품목 추가</button>
      <% end %>
    </div>
  <% else %>
    <div class="py-12 text-center">
      <div class="text-3xl mb-2">📋</div>
      <div class="text-sm text-gray-700 mb-1">품목이 아직 없습니다</div>
      <div class="text-xs text-gray-500 mb-4">견적성 첨부파일에서 [분석] 버튼을 눌러 추출하세요.</div>
      <%= form_with url: order_quote_items_path(order), data: { turbo_stream: true }, class: "inline" do %>
        <button type="submit" class="px-3 py-1.5 text-xs bg-gray-100 hover:bg-gray-200 rounded-md cursor-pointer">+ 직접 추가</button>
      <% end %>
    </div>
  <% end %>
</turbo-frame>
```

- [ ] **Step 3: 컨트롤러 create / destroy 추가**

`app/controllers/order_quote_items_controller.rb`에 액션 추가:
```ruby
  def create
    next_row = (@order.quote_items.maximum(:row_no) || 0) + 1
    item = @order.quote_items.create!(row_no: next_row, item: "")
    render turbo_stream: turbo_stream.append(
      "quote-items-tbody-#{@order.id}",
      partial: "orders/quote_item_row",
      locals: { item: item }
    )
  end

  def destroy
    item = @order.quote_items.find(params[:id])
    item.destroy
    render turbo_stream: turbo_stream.remove("quote-item-#{item.id}")
  end
```

- [ ] **Step 4: 회귀 테스트**

Run: `bin/rails test`
Expected: 모든 기존 테스트 PASS, 신규 컨트롤러 테스트는 Task 13에서 작성

- [ ] **Step 5: 커밋**

```bash
git add app/views/orders/_quote_items_frame.html.erb \
        app/views/orders/_quote_item_row.html.erb \
        app/controllers/order_quote_items_controller.rb
git commit -m "feat(quote-items): T12 — 7컬럼 표 + 출처 헤더 + 추가/삭제"
```

---

## Phase P4: 인라인 편집 (Stimulus + Turbo Stream)

### Task 13: PATCH 엔드포인트 + Stimulus 인라인 편집

**Files:**
- Modify: `app/controllers/order_quote_items_controller.rb` (update 액션)
- Create: `app/javascript/controllers/quote_item_inline_edit_controller.js`
- Create: `test/controllers/order_quote_items_controller_test.rb`

- [ ] **Step 1: 컨트롤러 테스트 작성**

`test/controllers/order_quote_items_controller_test.rb`:
```ruby
require "test_helper"

class OrderQuoteItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "qic@x.com", password: "Pass1234!", name: "QIC", role: "member")
    @order = Order.create!(reference_no: "QIC-1", title: "T", created_by: @user)
    @item = @order.quote_items.create!(row_no: 1, item: "Old")
    sign_in @user
  end

  test "update sets value + user_edited" do
    patch order_quote_item_path(@order, @item), params: { field: "item", value: "New" }, as: :turbo_stream
    assert_response :success
    @item.reload
    assert_equal "New", @item.item
    assert_equal true, @item.user_edited
    assert_equal @user.id, @item.edited_by_user_id
  end

  test "update rejects invalid field" do
    patch order_quote_item_path(@order, @item), params: { field: "ssn", value: "X" }, as: :turbo_stream
    assert_response :unprocessable_entity
  end

  test "destroy removes row" do
    assert_difference -> { OrderQuoteItem.count }, -1 do
      delete order_quote_item_path(@order, @item), as: :turbo_stream
    end
  end
end
```

- [ ] **Step 2: 테스트 실행 (실패 확인)**

Run: `bin/rails test test/controllers/order_quote_items_controller_test.rb -v`
Expected: FAIL (update 액션 없음 또는 화이트리스트 실패)

- [ ] **Step 3: 컨트롤러 update 추가**

`app/controllers/order_quote_items_controller.rb`에 추가:
```ruby
  ALLOWED_FIELDS = %w[item description model_part_no manufacturer_brand unit qty remarks].freeze

  def update
    item = @order.quote_items.find(params[:id])
    field = params[:field].to_s
    return head :unprocessable_entity unless ALLOWED_FIELDS.include?(field)

    item.update!(field => normalize(field, params[:value]),
                 user_edited: true, edited_by_user_id: current_user.id)
    render turbo_stream: turbo_stream.replace(
      "quote-item-#{item.id}", partial: "orders/quote_item_row", locals: { item: item }
    )
  end

  private

  def normalize(field, raw)
    return BigDecimal(raw.to_s.scan(/[\d.]+/).first || "0") if field == "qty" && raw.present?
    raw
  rescue ArgumentError
    nil
  end
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bin/rails test test/controllers/order_quote_items_controller_test.rb -v`
Expected: 3 runs, 0 failures

- [ ] **Step 5: Stimulus 컨트롤러 작성**

`app/javascript/controllers/quote_item_inline_edit_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("td[data-item-id]").forEach((td) => {
      td.addEventListener("dblclick", (e) => this.startEdit(td))
    })
  }

  startEdit(td) {
    if (td.dataset.editing === "1") return
    td.dataset.editing = "1"
    const original = td.querySelector(".quote-cell-text")?.textContent ?? td.textContent.trim()
    const field = td.dataset.field
    const id = td.dataset.itemId
    const isLong = field === "description" || field === "remarks"
    const input = document.createElement(isLong ? "textarea" : "input")
    input.value = original
    input.className = "w-full text-xs border border-[#00A1E0] rounded px-1 py-0.5"
    if (isLong) input.rows = 3
    td.innerHTML = ""
    td.appendChild(input)
    input.focus()
    input.addEventListener("blur", () => this.save(td, id, field, input.value))
    input.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { td.textContent = original; td.dataset.editing = "0" }
      if (e.key === "Enter" && !isLong) { e.preventDefault(); input.blur() }
    })
  }

  async save(td, id, field, value) {
    const orderId = this.element.id.replace("drawer-panel-", "").replace("-quote_items", "")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const fd = new FormData()
    fd.set("field", field)
    fd.set("value", value)
    fd.set("authenticity_token", token)
    const res = await fetch(`/orders/${orderId}/quote_items/${id}`, {
      method: "PATCH", body: fd, headers: { Accept: "text/vnd.turbo-stream.html" }
    })
    if (res.ok) {
      const html = await res.text()
      Turbo.renderStreamMessage(html)
    }
    td.dataset.editing = "0"
  }
}
```

- [ ] **Step 6: 수동 검증**

브라우저에서 견적성 첨부 분석 후 품목 셀 더블클릭 → 입력 → blur → 셀이 새 값 + 점 표시로 갱신되는지 확인.

- [ ] **Step 7: 커밋**

```bash
git add app/controllers/order_quote_items_controller.rb \
        app/javascript/controllers/quote_item_inline_edit_controller.js \
        test/controllers/order_quote_items_controller_test.rb
git commit -m "feat(quote-items): T13 — PATCH 엔드포인트 + Stimulus 인라인 편집"
```

---

## Phase P5: 재분석 + 잔액 부족 처리

### Task 14: 재분석 충돌 모달 (사용자 편집 보존)

**Files:**
- Modify: `app/views/orders/_quote_items_frame.html.erb` (재분석 버튼)
- Modify: `app/controllers/attachment_quote_analyses_controller.rb` (충돌 검출)

- [ ] **Step 1: 재분석 버튼을 frame 헤더에 추가**

`app/views/orders/_quote_items_frame.html.erb`의 출처 라인 옆에 추가:
```erb
<% sources.each do |s| %>
  <%= form_with url: reanalyze_attachment_quote_analysis_path(s),
      method: :post, data: { turbo_stream: true }, class: "inline ml-2" do %>
    <button type="submit" class="text-[10px] text-[#00A1E0] hover:underline cursor-pointer">[재분석]</button>
  <% end %>
<% end %>
```

- [ ] **Step 2: 컨트롤러에서 편집 보존 정책 명시**

`reanalyze` 액션 위에 주석 추가 (현재는 새 결과 시드 로직이 `seed_items`에서 단순 append라 사용자 편집 보존됨 — MVP 정책 만족):
```ruby
  # 정책: 재분석은 새 행을 append. 기존 사용자 편집 행은 보존.
  # P5+에서 충돌 모달(기존 유지/교체/병합) 도입 예정 (spec §14).
```

- [ ] **Step 3: 회귀 테스트**

Run: `bin/rails test`
Expected: PASS

- [ ] **Step 4: 커밋**

```bash
git add app/views/orders/_quote_items_frame.html.erb app/controllers/attachment_quote_analyses_controller.rb
git commit -m "feat(quote-items): T14 — 재분석 버튼 + 편집 보존 정책 (MVP append)"
```

---

## Phase P6: 캐릭터 저니 검증 + 회귀

### Task 15: Playwright 저니 시나리오

**Files:**
- Create: `test/system/quote_items_journey_test.rb`

- [ ] **Step 1: 저니 테스트 작성**

`test/system/quote_items_journey_test.rb`:
```ruby
require "application_system_test_case"

class QuoteItemsJourneyTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(email: "journey@x.com", password: "Pass1234!", name: "J", role: "member")
    @order = Order.create!(reference_no: "JNY-1", title: "Journey", created_by: @user, board_kind: "purchase")
    @order.attachments.attach(
      io: StringIO.new("dummy"), filename: "RFQ-100.pdf", content_type: "application/pdf"
    )
    QuoteItemExtractor.any_instance.stubs(:call).returns(
      items: [{ "item" => "SPILL TRAY", "description" => "129x119", "model_part_no" => "5004-BK",
                "manufacturer_brand" => "ENPAC", "unit" => "EA", "qty" => "16", "remarks" => "" }],
      cost_usd: 0.02, llm_model: "claude-sonnet-4-6", page_count: 1, latency_ms: 100
    )
    sign_in @user
  end

  test "분석 → 품목 탭 표시 → 인라인 편집" do
    visit order_path(@order)
    save_screenshot "/tmp/quote-items-journey-1.png"
    click_link "첨부파일"
    save_screenshot "/tmp/quote-items-journey-2.png"
    click_button "🔍 분석"
    perform_enqueued_jobs
    visit order_path(@order)
    click_link "품목"
    assert_text "SPILL TRAY"
    save_screenshot "/tmp/quote-items-journey-3.png"
  end
end
```

- [ ] **Step 2: 저니 실행**

Run: `bin/rails test test/system/quote_items_journey_test.rb -v`
Expected: PASS + 스크린샷 3개

- [ ] **Step 3: 전체 회귀**

Run: `bin/rails test`
Expected: 전체 PASS, 신규 ~15건 테스트 추가

- [ ] **Step 4: 커밋 + Push**

```bash
git add test/system/quote_items_journey_test.rb
git commit -m "test(quote-items): T15 — 캐릭터 저니 + 회귀 검증"
git push origin main
```

---

## Self-Review (Plan 작성자 자가 검토)

**Spec coverage:**
- R1 탭 신설 → Task 7 ✅
- R2 첨부 배지 → Task 11 ✅
- R3 휴리스틱 → Task 8 ✅
- R4 7컬럼 표 → Task 12 ✅
- R5 인라인 편집 → Task 13 ✅
- R6 Sonnet 4.6 → Task 9 ✅
- R7 수동 트리거 → Task 11 ✅
- R8 편집 보존 → Task 14 ✅ (MVP append 정책)
- R9 합산 표시 → Task 12 (sources 루프) ✅

**Placeholder scan:** 없음 (TBD/TODO 미사용, 모든 코드 블록 완전).

**Type consistency:** `OrderQuoteItem.row_no` Integer / `qty` Decimal — Task 2~13 일관. `AttachmentQuoteAnalysis.status` 문자열 enum 통일.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-11-quote-items-tab.md`. Two execution options:**

1. **Subagent-Driven (recommended)** — Task별 fresh subagent 디스패치, 사이에 리뷰 게이트
2. **Inline Execution** — 본 세션에서 executing-plans로 batch 실행 + 체크포인트

**어느 쪽으로 갈까요?** 또는 **검토** (plan 먼저 검토) / **커밋** (plan 문서 commit + push) 입력.
