# Feature Design: cpo-agent

> Plan: `docs/01-plan/features/cpo-agent.plan.md`

## 1. 데이터 모델

### 1.1 AgentInsight (신규 테이블)

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_agent_insights.rb
class CreateAgentInsights < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_insights do |t|
      t.references :order,    null: false, foreign_key: true
      t.references :supplier, foreign_key: true
      t.string     :insight_type, null: false  # price_comparison, supplier_risk, due_date_risk, cost_saving
      t.integer    :severity, default: 0       # enum: info(0), warning(1), alert(2)
      t.string     :title, null: false
      t.text       :body
      t.json       :metadata, default: {}      # 분석 수치 데이터
      t.boolean    :dismissed, default: false
      t.boolean    :useful                     # nil=미응답, true=유용, false=불필요
      t.datetime   :expires_at
      t.timestamps
    end

    add_index :agent_insights, [:order_id, :insight_type], name: "idx_insights_order_type"
    add_index :agent_insights, :expires_at
    add_index :agent_insights, [:dismissed, :expires_at], name: "idx_insights_active"
  end
end
```

### 1.2 AgentInsight 모델

```ruby
# app/models/agent_insight.rb
class AgentInsight < ApplicationRecord
  belongs_to :order
  belongs_to :supplier, optional: true

  enum :severity, { info: 0, warning: 1, alert: 2 }
  enum :insight_type, {
    price_comparison: "price_comparison",
    supplier_risk:    "supplier_risk",
    due_date_risk:    "due_date_risk",
    cost_saving:      "cost_saving"
  }

  validates :insight_type, :title, presence: true

  scope :active, -> {
    where(dismissed: false)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }
  scope :for_order, ->(order_id) { where(order_id: order_id).active.order(severity: :desc) }
  scope :for_dashboard, -> {
    active.where(severity: [:warning, :alert]).order(severity: :desc, created_at: :desc).limit(5)
  }

  # 동일 타입의 기존 Insight가 있으면 교체 (중복 방지)
  def self.upsert_for(order:, insight_type:, attrs: {})
    existing = find_by(order: order, insight_type: insight_type, dismissed: false)
    if existing
      existing.update!(attrs)
      existing
    else
      create!(attrs.merge(order: order, insight_type: insight_type))
    end
  end
end
```

## 2. 서비스 아키텍처

### 2.1 전체 구조

```
app/services/cpo_agent/
  ├── service.rb                    # 오케스트레이터 (4개 Analyzer 호출)
  ├── price_comparison_analyzer.rb  # 단가 비교
  ├── supplier_risk_analyzer.rb     # 거래처 리스크
  ├── due_date_risk_analyzer.rb     # 납기 위험
  └── cost_saving_analyzer.rb       # 비용 절감 기회
```

### 2.2 CpoAgent::Service (오케스트레이터)

```ruby
# app/services/cpo_agent/service.rb
module CpoAgent
  class Service
    ANALYZERS = [
      PriceComparisonAnalyzer,
      SupplierRiskAnalyzer,
      DueDateRiskAnalyzer,
      CostSavingAnalyzer
    ].freeze

    def self.analyze(order)
      new(order).analyze
    end

    def initialize(order)
      @order = order
    end

    def analyze
      insights = []
      ANALYZERS.each do |analyzer_class|
        result = analyzer_class.new(@order).call
        insights << result if result
      rescue => e
        Rails.logger.warn "[CpoAgent] #{analyzer_class}: #{e.message}"
      end
      insights.compact
    end
  end
end
```

### 2.3 PriceComparisonAnalyzer

```ruby
# app/services/cpo_agent/price_comparison_analyzer.rb
module CpoAgent
  class PriceComparisonAnalyzer
    THRESHOLD_PCT = 15  # ±15% 이상이면 Warning

    def initialize(order)
      @order = order
    end

    def call
      return nil unless @order.supplier_id && @order.estimated_value.to_f > 0

      # 동일 거래처의 과거 오더 단가 수집
      past_orders = Order.where(supplier_id: @order.supplier_id)
                         .where.not(id: @order.id)
                         .where.not(estimated_value: [nil, 0])
                         .order(created_at: :desc)
                         .limit(10)

      return nil if past_orders.count < 2

      avg_value = past_orders.average(:estimated_value).to_f
      current   = @order.estimated_value.to_f
      diff_pct  = ((current - avg_value) / avg_value * 100).round(1)

      return nil if diff_pct.abs < THRESHOLD_PCT

      severity = diff_pct > 30 ? :alert : :warning
      direction = diff_pct > 0 ? "높습니다" : "낮습니다"

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :price_comparison,
        attrs: {
          severity: severity,
          supplier: @order.supplier,
          title: "단가가 평균 대비 #{diff_pct.abs}% #{direction}",
          body: "이 거래처의 최근 #{past_orders.count}건 평균 금액: $#{'%.0f' % avg_value} → 현재: $#{'%.0f' % current}",
          metadata: {
            avg_value: avg_value.round(2),
            current_value: current,
            diff_pct: diff_pct,
            sample_count: past_orders.count
          },
          expires_at: 7.days.from_now
        }
      )
    end
  end
end
```

### 2.4 SupplierRiskAnalyzer

```ruby
# app/services/cpo_agent/supplier_risk_analyzer.rb
module CpoAgent
  class SupplierRiskAnalyzer
    DELIVERY_RATE_THRESHOLD = 80  # 80% 미만이면 Alert

    def initialize(order)
      @order = order
    end

    def call
      return nil unless @order.supplier_id
      supplier = @order.supplier

      # 납기 준수율 계산
      total = supplier.orders.where(status: :get_grn).count
      return nil if total < 3  # 데이터 부족

      on_time = supplier.orders.where(status: :get_grn)
                        .where("due_date IS NOT NULL AND updated_at <= due_date + 1")
                        .count
      rate = (on_time.to_f / total * 100).round(1)

      # credit_grade 기반 추가 판단
      grade_risk = %w[C D].include?(supplier.credit_grade)

      return nil if rate >= DELIVERY_RATE_THRESHOLD && !grade_risk

      severity = rate < 60 || supplier.credit_grade == "D" ? :alert : :warning

      title_parts = []
      title_parts << "납기 준수율 #{rate}%" if rate < DELIVERY_RATE_THRESHOLD
      title_parts << "신용등급 #{supplier.credit_grade}" if grade_risk

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :supplier_risk,
        attrs: {
          severity: severity,
          supplier: supplier,
          title: "거래처 주의: #{title_parts.join(' / ')}",
          body: "#{supplier.name} — 총 #{total}건 중 #{on_time}건 정시 납품",
          metadata: {
            delivery_rate: rate,
            total_orders: total,
            on_time_orders: on_time,
            credit_grade: supplier.credit_grade
          },
          expires_at: 3.days.from_now
        }
      )
    end
  end
end
```

### 2.5 DueDateRiskAnalyzer

```ruby
# app/services/cpo_agent/due_date_risk_analyzer.rb
module CpoAgent
  class DueDateRiskAnalyzer
    def initialize(order)
      @order = order
    end

    def call
      return nil if @order.due_date.nil?
      return nil if @order.get_grn? || @order.give_up?

      days_left = (@order.due_date - Date.today).to_i
      return nil if days_left > 7  # 7일 이상 남으면 무시

      # RiskAssessmentService 결과 활용
      risk = RiskAssessmentService.calculate(@order)

      severity = case days_left
                 when ..-1 then :alert      # 이미 지연
                 when 0..3 then :alert      # D-3 이내
                 else :warning              # D-7 이내
                 end

      overdue_label = days_left < 0 ? "#{days_left.abs}일 지연" : "D-#{days_left}"

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :due_date_risk,
        attrs: {
          severity: severity,
          title: "납기 #{overdue_label} — 위험도 #{risk[:level]}",
          body: "납기일: #{@order.due_date.strftime('%Y-%m-%d')} / 현재 상태: #{Order::STATUS_LABELS[@order.status]}",
          metadata: {
            days_left: days_left,
            risk_score: risk[:score],
            risk_level: risk[:level],
            current_status: @order.status
          },
          expires_at: 1.day.from_now
        }
      )
    end
  end
end
```

### 2.6 CostSavingAnalyzer

```ruby
# app/services/cpo_agent/cost_saving_analyzer.rb
module CpoAgent
  class CostSavingAnalyzer
    def initialize(order)
      @order = order
    end

    def call
      return nil unless @order.supplier_id && @order.estimated_value.to_f > 0

      # 동일 품목(title 유사)을 다른 거래처에서 더 싸게 구매한 이력 찾기
      cheaper = OrderQuote.joins(:supplier)
                          .where(order_id: Order.where.not(supplier_id: @order.supplier_id)
                                                .where("title LIKE ?", "%#{@order.title.first(20)}%")
                                                .select(:id))
                          .where("unit_price > 0")
                          .order(:unit_price)
                          .limit(3)

      return nil if cheaper.empty?

      best = cheaper.first
      current_price = @order.estimated_value.to_f
      saving = current_price - best.unit_price.to_f
      return nil if saving <= 0

      saving_pct = (saving / current_price * 100).round(1)
      return nil if saving_pct < 5  # 5% 미만 절감은 무시

      AgentInsight.upsert_for(
        order: @order,
        insight_type: :cost_saving,
        attrs: {
          severity: :info,
          supplier: best.supplier,
          title: "비용 절감 기회: #{best.supplier.name}에서 #{saving_pct}% 저렴",
          body: "대체 거래처 #{cheaper.count}곳 발견. 최저가: $#{'%.0f' % best.unit_price} (현재: $#{'%.0f' % current_price})",
          metadata: {
            current_price: current_price,
            best_price: best.unit_price.to_f,
            saving_amount: saving.round(2),
            saving_pct: saving_pct,
            alternative_supplier: best.supplier.name,
            alternatives_count: cheaper.count
          },
          expires_at: 14.days.from_now
        }
      )
    end
  end
end
```

## 3. Background Job

```ruby
# app/jobs/agent_insight_job.rb
class AgentInsightJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.includes(:supplier, :client, :order_quotes).find_by(id: order_id)
    return unless order

    CpoAgent::Service.analyze(order)
    Rails.logger.info "[AgentInsightJob] Analyzed order ##{order_id}"
  rescue => e
    Rails.logger.error "[AgentInsightJob] Error for order ##{order_id}: #{e.message}"
  end
end
```

## 4. Controller 연동

### 4.1 AgentInsightsController (피드백/dismiss)

```ruby
# app/controllers/agent_insights_controller.rb
class AgentInsightsController < ApplicationController
  def dismiss
    insight = AgentInsight.find(params[:id])
    insight.update!(dismissed: true)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("agent-insight-#{insight.id}")
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def feedback
    insight = AgentInsight.find(params[:id])
    insight.update!(useful: params[:useful] == "true")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "agent-insight-#{insight.id}",
          partial: "agent_insights/insight",
          locals: { insight: insight }
        )
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
```

### 4.2 기존 Controller 트리거 포인트

```ruby
# app/controllers/orders_controller.rb — show 액션에 추가
def show
  @order = Order.find(params[:id])
  # ... 기존 코드 ...

  # Agent 분석 트리거 (비동기)
  AgentInsightJob.perform_later(@order.id)

  # 기존 Insight 로드 (즉시 표시용)
  @agent_insights = @order.agent_insights.active.order(severity: :desc).limit(3)
end
```

### 4.3 Routes

```ruby
# config/routes.rb 에 추가
resources :agent_insights, only: [] do
  member do
    patch :dismiss
    patch :feedback
  end
end
```

## 5. UI 설계

### 5.1 오더 드로어 상단 배너

**위치**: `_drawer_content.html.erb` 탭 바 바로 아래, 패널 시작 전

```erb
<%# app/views/agent_insights/_drawer_banner.html.erb %>
<% if insights.any? %>
  <div id="agent-insights-<%= order.id %>" class="px-6 pt-4 space-y-2">
    <% insights.each do |insight| %>
      <%= render "agent_insights/insight", insight: insight %>
    <% end %>
  </div>
<% end %>
```

### 5.2 개별 Insight 카드

```erb
<%# app/views/agent_insights/_insight.html.erb %>
<%
  bg_class = case insight.severity
             when "alert"   then "bg-red-50 border-red-200 dark:bg-red-900/20 dark:border-red-800"
             when "warning" then "bg-amber-50 border-amber-200 dark:bg-amber-900/20 dark:border-amber-800"
             else                "bg-gray-50 border-gray-200 dark:bg-gray-800 dark:border-gray-700"
             end
  icon_class = case insight.severity
               when "alert"   then "text-red-600 dark:text-red-400"
               when "warning" then "text-amber-600 dark:text-amber-400"
               else                "text-gray-500 dark:text-gray-400"
               end
  type_icon = case insight.insight_type
              when "price_comparison" then '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>'
              when "supplier_risk"   then '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>'
              when "due_date_risk"   then '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>'
              when "cost_saving"     then '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>'
              end
%>
<div id="agent-insight-<%= insight.id %>"
     class="flex items-start gap-3 p-3 rounded-lg border <%= bg_class %>">
  <!-- 아이콘 -->
  <svg class="w-4 h-4 mt-0.5 flex-shrink-0 <%= icon_class %>" viewBox="0 0 24 24"
       fill="none" stroke="currentColor" stroke-width="2"
       stroke-linecap="round" stroke-linejoin="round">
    <%= raw type_icon %>
  </svg>

  <!-- 내용 -->
  <div class="flex-1 min-w-0">
    <p class="text-sm font-medium text-gray-900 dark:text-white"><%= insight.title %></p>
    <p class="text-xs text-gray-500 dark:text-gray-400 mt-0.5"><%= insight.body %></p>
  </div>

  <!-- 액션 버튼 -->
  <div class="flex items-center gap-1 flex-shrink-0">
    <% unless insight.useful == true %>
      <%= button_to dismiss_agent_insight_path(insight),
            method: :patch, data: { turbo: true },
            class: "p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors",
            title: "무시" do %>
        <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor"
             stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      <% end %>
    <% end %>

    <% if insight.useful.nil? %>
      <%= button_to feedback_agent_insight_path(insight, useful: true),
            method: :patch, data: { turbo: true },
            class: "p-1 text-gray-400 hover:text-green-600 transition-colors",
            title: "유용함" do %>
        <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor"
             stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3H14z"/>
          <path d="M7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"/>
        </svg>
      <% end %>
    <% elsif insight.useful == true %>
      <span class="text-xs text-green-600 dark:text-green-400 font-medium">감사합니다</span>
    <% end %>
  </div>
</div>
```

### 5.3 대시보드 Agent 브리핑 위젯

**위치**: `dashboard/index.html.erb` KPI 카드 아래, 차트 위

```erb
<%# app/views/dashboard/_agent_briefing.html.erb %>
<% if @agent_briefing.any? %>
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-5 mb-6">
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center gap-2">
        <div class="w-8 h-8 rounded-lg bg-indigo-50 dark:bg-indigo-900/30 flex items-center justify-center">
          <svg class="w-4 h-4 text-indigo-600 dark:text-indigo-400" viewBox="0 0 24 24"
               fill="none" stroke="currentColor" stroke-width="2"
               stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
          </svg>
        </div>
        <div>
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white">CPO Agent 브리핑</h3>
          <p class="text-xs text-gray-500 dark:text-gray-400">오늘의 주요 알림</p>
        </div>
      </div>
      <span class="text-xs font-medium text-indigo-600 dark:text-indigo-400 bg-indigo-50 dark:bg-indigo-900/30 px-2 py-0.5 rounded-full">
        <%= @agent_briefing.count %>건
      </span>
    </div>

    <div class="space-y-2">
      <% @agent_briefing.each do |insight| %>
        <%= render "agent_insights/insight", insight: insight %>
      <% end %>
    </div>
  </div>
<% end %>
```

### 5.4 DashboardController 수정

```ruby
# app/controllers/dashboard_controller.rb — index 액션에 추가
def index
  # ... 기존 KPI 코드 ...

  # CPO Agent 브리핑
  @agent_briefing = AgentInsight.for_dashboard
end
```

## 6. 구현 순서

| # | 파일 | 유형 | 설명 |
|---|------|------|------|
| 1 | `db/migrate/..._create_agent_insights.rb` | Migration | 테이블 생성 |
| 2 | `app/models/agent_insight.rb` | Model | enum, scope, upsert_for |
| 3 | `app/services/cpo_agent/service.rb` | Service | 오케스트레이터 |
| 4 | `app/services/cpo_agent/price_comparison_analyzer.rb` | Service | 단가 비교 |
| 5 | `app/services/cpo_agent/supplier_risk_analyzer.rb` | Service | 거래처 리스크 |
| 6 | `app/services/cpo_agent/due_date_risk_analyzer.rb` | Service | 납기 위험 |
| 7 | `app/services/cpo_agent/cost_saving_analyzer.rb` | Service | 비용 절감 |
| 8 | `app/jobs/agent_insight_job.rb` | Job | Solid Queue 백그라운드 |
| 9 | `app/controllers/agent_insights_controller.rb` | Controller | dismiss/feedback |
| 10 | `config/routes.rb` | Config | 라우트 추가 |
| 11 | `app/views/agent_insights/_insight.html.erb` | View | 개별 Insight 카드 |
| 12 | `app/views/agent_insights/_drawer_banner.html.erb` | View | 드로어 배너 |
| 13 | `app/views/orders/_drawer_content.html.erb` | View | 배너 삽입 (수정) |
| 14 | `app/views/dashboard/_agent_briefing.html.erb` | View | 대시보드 위젯 |
| 15 | `app/views/dashboard/index.html.erb` | View | 위젯 삽입 (수정) |
| 16 | `app/controllers/orders_controller.rb` | Controller | show에 Job 트리거 (수정) |
| 17 | `app/controllers/dashboard_controller.rb` | Controller | briefing 로드 (수정) |

## 7. Turbo Stream ID 규칙

| ID 패턴 | 용도 |
|---------|------|
| `agent-insights-{order_id}` | 드로어 내 Insight 컨테이너 |
| `agent-insight-{insight_id}` | 개별 Insight 카드 (dismiss/feedback 타겟) |
| `agent-briefing` | 대시보드 브리핑 위젯 컨테이너 |

## 8. 성능 고려

| 항목 | 대응 |
|------|------|
| 드로어 열 때마다 Job 실행 | 같은 order에 대해 최근 5분 내 분석 건너뛰기 (Job 내 guard) |
| N+1 쿼리 | `Order.includes(:supplier, :order_quotes)` |
| 만료 데이터 누적 | 매일 cron으로 `AgentInsight.where("expires_at < ?", Time.current).delete_all` |
| Dashboard 쿼리 | `for_dashboard` scope에 인덱스 활용 (`idx_insights_active`) |

## 9. 테스트 체크리스트

- [ ] `AgentInsight` 모델 validation/enum 동작
- [ ] `upsert_for` 중복 방지 확인
- [ ] 각 Analyzer: 데이터 부족 시 nil 반환
- [ ] 각 Analyzer: 임계값 초과 시 올바른 severity
- [ ] `AgentInsightJob` 에러 시 로그만 남기고 실패하지 않음
- [ ] dismiss → Turbo Stream remove 동작
- [ ] feedback → 카드 업데이트 동작
- [ ] 드로어에서 Insight 배너 렌더링
- [ ] 대시보드에서 브리핑 위젯 렌더링
- [ ] 만료된 Insight 숨김 확인
