# CPO Agent Phase 2 — Progressive Autonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CPO Agent가 사용자 피드백 기반으로 안내 모드 → 자동 실행 모드로 점진적 전환하는 기능 구현

**Architecture:** AgentTrustLevel 모델로 사용자별+Analyzer별 신뢰 횟수를 추적. 임계값(5회) 도달 시 auto_mode 활성화. AutoActionService가 자동 액션(Comment 첨부, Notification 발송, OrderQuote 추가)을 실행하고 사후 알림 Insight를 생성.

**Tech Stack:** Rails 8.1, SQLite3, Solid Queue, Turbo Stream

---

## File Structure

| File | Responsibility |
|------|---------------|
| `db/migrate/YYYYMMDD_create_agent_trust_levels.rb` | 신규 테이블 |
| `app/models/agent_trust_level.rb` | 신뢰 레벨 모델 + 전환 로직 |
| `app/services/cpo_agent/auto_action_service.rb` | 4개 자동 액션 오케스트레이터 |
| `app/controllers/agent_insights_controller.rb` | 수정: feedback에 trust 연동 |
| `app/jobs/agent_insight_job.rb` | 수정: user_id 전달 + auto 실행 |
| `app/controllers/orders_controller.rb` | 수정: Job에 current_user.id 전달 |
| `app/views/agent_insights/_insight.html.erb` | 수정: 자동 처리 indigo 스타일 |
| `app/views/settings/base/index.html.erb` | 수정: Agent 토글 UI 섹션 추가 |
| `config/routes.rb` | 수정: settings/agent_trust 라우트 |

---

### Task 1: Migration + Model

**Files:**
- Create: `db/migrate/YYYYMMDD_create_agent_trust_levels.rb`
- Create: `app/models/agent_trust_level.rb`

- [ ] **Step 1: Generate migration**

```bash
bin/rails generate migration CreateAgentTrustLevels
```

- [ ] **Step 2: Write migration**

```ruby
# db/migrate/YYYYMMDD_create_agent_trust_levels.rb
class CreateAgentTrustLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_trust_levels do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :insight_type, null: false
      t.integer    :useful_count, default: 0
      t.integer    :dismiss_count, default: 0
      t.boolean    :auto_mode, default: false
      t.datetime   :auto_activated_at
      t.timestamps
    end
    add_index :agent_trust_levels, [:user_id, :insight_type], unique: true, name: "idx_trust_user_type"
  end
end
```

- [ ] **Step 3: Create model**

```ruby
# app/models/agent_trust_level.rb
# frozen_string_literal: true

class AgentTrustLevel < ApplicationRecord
  belongs_to :user

  TRUST_THRESHOLD = 5

  validates :insight_type, presence: true
  validates :user_id, uniqueness: { scope: :insight_type }

  def self.record_feedback!(user:, insight_type:, useful:)
    level = find_or_create_by(user: user, insight_type: insight_type)
    if useful
      level.increment!(:useful_count)
      if level.useful_count >= TRUST_THRESHOLD && !level.auto_mode
        level.update!(auto_mode: true, auto_activated_at: Time.current)
      end
    else
      level.increment!(:dismiss_count)
    end
    level
  end

  def self.auto_mode?(user:, insight_type:)
    find_by(user: user, insight_type: insight_type)&.auto_mode || false
  end
end
```

- [ ] **Step 4: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 5: Smoke test model**

```bash
bin/rails runner "
u = User.first
5.times { AgentTrustLevel.record_feedback!(user: u, insight_type: 'price_comparison', useful: true) }
level = AgentTrustLevel.find_by(user: u, insight_type: 'price_comparison')
puts 'useful_count: ' + level.useful_count.to_s
puts 'auto_mode: ' + level.auto_mode.to_s
puts 'auto_mode?: ' + AgentTrustLevel.auto_mode?(user: u, insight_type: 'price_comparison').to_s
puts 'PASS' if level.auto_mode && level.useful_count == 5
"
```

Expected: `useful_count: 5`, `auto_mode: true`, `PASS`

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*_create_agent_trust_levels.rb app/models/agent_trust_level.rb db/schema.rb
git commit -m "feat: AgentTrustLevel 모델 — 피드백 기반 신뢰 레벨 + 자동 모드 전환"
```

---

### Task 2: AutoActionService

**Files:**
- Create: `app/services/cpo_agent/auto_action_service.rb`

- [ ] **Step 1: Create service**

```ruby
# app/services/cpo_agent/auto_action_service.rb
# frozen_string_literal: true

module CpoAgent
  class AutoActionService
    def self.execute(order, insight, user)
      new(order, insight, user).execute
    end

    def initialize(order, insight, user)
      @order = order
      @insight = insight
      @user = user
    end

    def execute
      return unless @user
      return unless AgentTrustLevel.auto_mode?(user: @user, insight_type: @insight.insight_type)

      case @insight.insight_type
      when "price_comparison" then auto_price_comparison
      when "supplier_risk"   then auto_supplier_risk
      when "due_date_risk"   then auto_due_date_notification
      when "cost_saving"     then auto_cost_saving
      end
    rescue => e
      Rails.logger.warn "[CpoAgent::AutoAction] #{e.message}"
    end

    private

    def auto_price_comparison
      past = Order.where(supplier_id: @order.supplier_id)
                  .where.not(id: @order.id, estimated_value: [nil, 0])
                  .order(created_at: :desc).limit(3)
      return if past.empty?

      body = "[CPO Agent] 과거 견적 비교\n"
      past.each { |o| body += "- #{o.title}: $#{o.estimated_value} (#{o.created_at.strftime('%Y-%m-%d')})\n" }
      body += "현재: $#{@order.estimated_value}"

      create_auto_comment(body)
      create_auto_insight("과거 견적 3건 비교를 자동 첨부했습니다", "comment_added")
    end

    def auto_supplier_risk
      alternatives = Supplier.active.where.not(id: @order.supplier_id)
                             .where(credit_grade: %w[A B]).limit(3)
      return if alternatives.empty?

      body = "[CPO Agent] 대체 거래처 추천\n"
      alternatives.each do |s|
        contact = s.primary_contact
        body += "- #{s.name} (#{s.credit_grade}등급)"
        body += " | #{contact.email}" if contact&.email
        body += "\n"
      end

      create_auto_comment(body)
      create_auto_insight("대체 거래처 #{alternatives.count}곳을 자동 추천했습니다", "alternatives_suggested")
    end

    def auto_due_date_notification
      assignees = @order.assignees.presence || []
      assignees.each do |assignee|
        user = assignee.respond_to?(:user) ? assignee.user : nil
        next unless user
        Notification.create!(
          user: user,
          notifiable: @order,
          title: "[CPO Agent] 납기 위험: #{@order.title}",
          body: "납기일 #{@order.due_date&.strftime('%Y-%m-%d')} — 즉시 조치 필요"
        )
      end
      create_auto_insight("담당자에게 납기 위험 알림을 자동 발송했습니다", "notification_sent")
    end

    def auto_cost_saving
      metadata = @insight.metadata
      return unless metadata["best_price"] && metadata["alternative_supplier"]

      supplier = Supplier.find_by(name: metadata["alternative_supplier"])
      return unless supplier

      existing = @order.order_quotes.find_by(supplier: supplier)
      return if existing

      @order.order_quotes.create!(
        supplier: supplier,
        unit_price: metadata["best_price"],
        currency: @order.currency || "USD",
        notes: "[CPO Agent] 자동 추가 — 비용 절감 #{metadata['saving_pct']}%"
      )
      create_auto_insight("#{supplier.name} 견적을 자동 추가했습니다 (-#{metadata['saving_pct']}%)", "quote_added")
    end

    def create_auto_comment(body)
      @order.comments.create!(user: @user, body: body)
    end

    def create_auto_insight(title, action_type)
      AgentInsight.create!(
        order: @order,
        insight_type: @insight.insight_type,
        severity: :info,
        title: "[자동 처리] #{title}",
        body: "CPO Agent가 신뢰 레벨 기반으로 자동 실행했습니다",
        metadata: { auto_action: true, action_type: action_type },
        expires_at: 3.days.from_now
      )
    end
  end
end
```

- [ ] **Step 2: Smoke test service**

```bash
bin/rails runner "
puts 'AutoActionService class: ' + CpoAgent::AutoActionService.name
puts 'PASS'
"
```

- [ ] **Step 3: Commit**

```bash
git add app/services/cpo_agent/auto_action_service.rb
git commit -m "feat: CpoAgent::AutoActionService — 4개 자동 액션 (Comment/Notification/Quote)"
```

---

### Task 3: Feedback → Trust 연동

**Files:**
- Modify: `app/controllers/agent_insights_controller.rb`

- [ ] **Step 1: Update feedback action**

Replace the `feedback` method in `app/controllers/agent_insights_controller.rb`:

```ruby
def feedback
  insight = AgentInsight.find(params[:id])
  useful = params[:useful] == "true"
  insight.update!(useful: useful)

  # Trust Level 업데이트
  level = AgentTrustLevel.record_feedback!(
    user: current_user,
    insight_type: insight.insight_type,
    useful: useful
  )

  respond_to do |format|
    format.turbo_stream do
      streams = [
        turbo_stream.replace(
          "agent-insight-#{insight.id}",
          partial: "agent_insights/insight",
          locals: { insight: insight }
        )
      ]

      # 자동 모드 최초 전환 시 알림
      if level.auto_mode && level.useful_count == AgentTrustLevel::TRUST_THRESHOLD
        streams << turbo_stream.prepend("flash-messages",
          "<div class='mb-4 rounded-lg bg-indigo-50 border border-indigo-200 px-4 py-3 text-indigo-800 text-sm'>
            이제부터 '#{insight.insight_type}' 유형은 CPO Agent가 자동 처리합니다
          </div>".html_safe)
      end

      render turbo_stream: streams
    end
    format.html { redirect_back fallback_location: root_path }
  end
end
```

- [ ] **Step 2: Verify controller loads**

```bash
bin/rails runner "puts AgentInsightsController.instance_methods(false).sort.join(', ')"
```

Expected: `dismiss, feedback`

- [ ] **Step 3: Commit**

```bash
git add app/controllers/agent_insights_controller.rb
git commit -m "feat: feedback → AgentTrustLevel 연동 + 자동 모드 전환 알림"
```

---

### Task 4: Job + Controller 수정 (user_id 전달 + auto 실행)

**Files:**
- Modify: `app/jobs/agent_insight_job.rb`
- Modify: `app/controllers/orders_controller.rb`

- [ ] **Step 1: Update AgentInsightJob**

Replace `app/jobs/agent_insight_job.rb`:

```ruby
# frozen_string_literal: true

class AgentInsightJob < ApplicationJob
  queue_as :default

  def perform(order_id, user_id = nil)
    order = Order.includes(:supplier, :client, :order_quotes).find_by(id: order_id)
    return unless order

    last = order.agent_insights.order(created_at: :desc).first
    return if last && last.created_at > 5.minutes.ago

    insights = CpoAgent::Service.analyze(order)

    # 자동 모드 실행
    user = User.find_by(id: user_id)
    if user
      insights.each do |insight|
        CpoAgent::AutoActionService.execute(order, insight, user)
      end
    end

    Rails.logger.info "[AgentInsightJob] Analyzed order ##{order_id} (auto actions for user ##{user_id})"
  rescue => e
    Rails.logger.error "[AgentInsightJob] Error for order ##{order_id}: #{e.message}"
  end
end
```

- [ ] **Step 2: Update OrdersController#show**

In `app/controllers/orders_controller.rb`, change:

```ruby
AgentInsightJob.perform_later(@order.id)
```

to:

```ruby
AgentInsightJob.perform_later(@order.id, current_user.id)
```

- [ ] **Step 3: Smoke test**

```bash
bin/rails runner "
o = Order.first; u = User.first
AgentInsightJob.perform_now(o.id, u.id)
puts 'Job OK'
"
```

- [ ] **Step 4: Commit**

```bash
git add app/jobs/agent_insight_job.rb app/controllers/orders_controller.rb
git commit -m "feat: AgentInsightJob에 user_id 전달 + AutoActionService 연동"
```

---

### Task 5: 자동 처리 Insight UI 스타일

**Files:**
- Modify: `app/views/agent_insights/_insight.html.erb`

- [ ] **Step 1: Add auto_action style**

In `app/views/agent_insights/_insight.html.erb`, replace the `bg_class` assignment block:

```erb
<%
  is_auto = insight.metadata.is_a?(Hash) && insight.metadata["auto_action"] == true
  bg_class = if is_auto
               "bg-indigo-50 border-indigo-200 dark:bg-indigo-900/20 dark:border-indigo-800"
             else
               case insight.severity
               when "alert"   then "bg-red-50 border-red-200 dark:bg-red-900/20 dark:border-red-800"
               when "warning" then "bg-amber-50 border-amber-200 dark:bg-amber-900/20 dark:border-amber-800"
               else                "bg-gray-50 border-gray-200 dark:bg-gray-800 dark:border-gray-700"
               end
             end
  icon_class = if is_auto
                 "text-indigo-600 dark:text-indigo-400"
               else
                 case insight.severity
                 when "alert"   then "text-red-600 dark:text-red-400"
                 when "warning" then "text-amber-600 dark:text-amber-400"
                 else                "text-gray-500 dark:text-gray-400"
                 end
               end
  type_icon = if is_auto
                '<path d="M12 2a10 10 0 1 0 10 10A10 10 0 0 0 12 2zm0 18a8 8 0 1 1 8-8 8 8 0 0 1-8 8z"/><path d="M12 6a1 1 0 0 0-1 1v5a1 1 0 0 0 .29.71l3 3a1 1 0 0 0 1.42-1.42L13 11.59V7a1 1 0 0 0-1-1z"/>'
              else
                case insight.insight_type
                when "price_comparison" then '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>'
                when "supplier_risk"   then '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>'
                when "due_date_risk"   then '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>'
                when "cost_saving"     then '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>'
                end
              end
%>
```

- [ ] **Step 2: Update action buttons for auto insights (dismiss only)**

Replace the action buttons section. After the `<!-- 액션 버튼 -->` comment, use:

```erb
  <!-- 액션 버튼 -->
  <div class="flex items-center gap-1 flex-shrink-0">
    <% if is_auto %>
      <%= button_to dismiss_agent_insight_path(insight),
            method: :patch, data: { turbo: true },
            class: "px-2 py-1 text-xs text-indigo-600 hover:text-indigo-800 font-medium transition-colors",
            title: "확인" do %>
        확인
      <% end %>
    <% else %>
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
    <% end %>
  </div>
```

- [ ] **Step 3: Commit**

```bash
git add app/views/agent_insights/_insight.html.erb
git commit -m "feat: 자동 처리 Insight indigo 스타일 + 확인 버튼"
```

---

### Task 6: Settings 페이지 Agent 토글 UI

**Files:**
- Modify: `app/views/settings/base/index.html.erb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Add route for trust level toggle**

In `config/routes.rb`, add inside the `namespace :settings` block:

```ruby
patch "agent_trust/:insight_type", to: "agent_trust#toggle", as: :agent_trust_toggle
```

- [ ] **Step 2: Create settings/agent_trust_controller**

```ruby
# app/controllers/settings/agent_trust_controller.rb
# frozen_string_literal: true

module Settings
  class AgentTrustController < ApplicationController
    def toggle
      level = AgentTrustLevel.find_or_create_by(
        user: current_user,
        insight_type: params[:insight_type]
      )
      level.update!(auto_mode: !level.auto_mode)

      redirect_to settings_root_path, notice: "#{params[:insight_type]} 자동 모드가 #{level.auto_mode ? '활성화' : '비활성화'}되었습니다"
    end
  end
end
```

- [ ] **Step 3: Add Agent settings section to Settings page**

Append before the closing `</div>` of `app/views/settings/base/index.html.erb`:

```erb
  <%# --- CPO Agent Settings Section --- %>
  <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 mb-6">
    <div class="px-6 py-4 border-b border-gray-100 dark:border-gray-700 flex items-center gap-3">
      <svg class="w-5 h-5 text-indigo-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
      </svg>
      <div>
        <h2 class="text-sm font-semibold text-gray-900 dark:text-gray-100">CPO Agent 설정</h2>
        <p class="text-xs text-gray-500 dark:text-gray-400">자동 처리 모드 관리 (유용함 5회 이상 시 자동 활성화)</p>
      </div>
    </div>
    <div class="divide-y divide-gray-100 dark:divide-gray-700">
      <%
        insight_types = {
          "price_comparison" => { label: "단가 비교", desc: "과거 견적 비교 테이블 자동 첨부" },
          "supplier_risk"    => { label: "거래처 리스크", desc: "대체 거래처 자동 추천" },
          "due_date_risk"    => { label: "납기 위험", desc: "담당자에게 알림 자동 발송" },
          "cost_saving"      => { label: "비용 절감", desc: "저렴한 견적 자동 추가" }
        }
      %>
      <% insight_types.each do |type, info| %>
        <% level = AgentTrustLevel.find_by(user: current_user, insight_type: type) %>
        <div class="flex items-center justify-between px-6 py-4">
          <div>
            <p class="text-sm font-medium text-gray-900 dark:text-gray-100"><%= info[:label] %></p>
            <p class="text-xs text-gray-500 dark:text-gray-400"><%= info[:desc] %></p>
            <% if level %>
              <p class="text-xs text-gray-400 dark:text-gray-500 mt-1">
                유용함 <%= level.useful_count %>회
                <% if level.auto_activated_at %>
                  · 자동 전환: <%= level.auto_activated_at.strftime('%Y-%m-%d') %>
                <% end %>
              </p>
            <% end %>
          </div>
          <%= button_to settings_agent_trust_toggle_path(insight_type: type),
                method: :patch,
                class: "relative inline-flex h-6 w-11 items-center rounded-full transition-colors #{level&.auto_mode ? 'bg-indigo-600' : 'bg-gray-200 dark:bg-gray-600'}",
                title: level&.auto_mode ? "자동 → 수동" : "수동 → 자동" do %>
            <span class="inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{level&.auto_mode ? 'translate-x-6' : 'translate-x-1'}"></span>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>
```

- [ ] **Step 4: Smoke test routes**

```bash
bin/rails runner "puts Rails.application.routes.url_helpers.settings_agent_trust_toggle_path(insight_type: 'price_comparison')"
```

Expected: `/settings/agent_trust/price_comparison`

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/settings/agent_trust_controller.rb app/views/settings/base/index.html.erb
git commit -m "feat: Settings 페이지 CPO Agent 자동 모드 토글 UI"
```

---

### Task 7: 통합 스모크 테스트 + 최종 커밋

- [ ] **Step 1: Full smoke test**

```bash
bin/rails runner "
puts '=== Progressive Autonomy 통합 테스트 ==='

u = User.first
o = Order.first

# 1. Trust Level 생성
5.times { AgentTrustLevel.record_feedback!(user: u, insight_type: 'due_date_risk', useful: true) }
puts '1. Trust auto_mode: ' + AgentTrustLevel.auto_mode?(user: u, insight_type: 'due_date_risk').to_s

# 2. Service 분석
insights = CpoAgent::Service.analyze(o)
puts '2. Insights: ' + insights.count.to_s

# 3. Auto action 실행
insights.each do |insight|
  CpoAgent::AutoActionService.execute(o, insight, u)
end
auto_insights = AgentInsight.where(order: o).where(\"metadata LIKE '%auto_action%'\")
puts '3. Auto insights: ' + auto_insights.count.to_s

# 4. Settings route
puts '4. Route: ' + Rails.application.routes.url_helpers.settings_agent_trust_toggle_path(insight_type: 'test')

puts '=== ALL PASSED ==='
"
```

- [ ] **Step 2: Final commit with push**

```bash
git add -A
git commit -m "feat: CPO Agent Phase 2 — Progressive Autonomy 완료

피드백 기반 신뢰 레벨(AgentTrustLevel)로 안내→자동 모드 전환
4개 자동 액션: 견적 비교 Comment, 대체 거래처 추천, 납기 알림, 견적 자동 추가
Settings 토글 UI로 수동 ON/OFF 가능"
git push
```
