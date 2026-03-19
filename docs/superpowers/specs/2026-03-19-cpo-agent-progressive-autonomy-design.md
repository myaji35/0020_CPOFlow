# CPO Agent Phase 2 — Progressive Autonomy

> 초기 안내 모드에서 자동 실행 모드로 점진적 전환

## Problem

CPO Agent Phase 1은 모든 Insight를 배너로 표시하고 사용자가 수동으로 확인/무시한다. 반복적으로 "유용함"을 누르는 패턴이 생기면, Agent가 알아서 조치하는 편이 효율적이다.

## Solution: 피드백 기반 신뢰 레벨

사용자가 같은 유형의 Insight에 [유용함]을 5회 이상 누르면, 해당 유형에 대해 Agent가 자동으로 액션을 실행한다. 자동 처리 후 사후 알림 카드로 보고한다.

## Data Model

### AgentTrustLevel (신규 테이블)

```sql
CREATE TABLE agent_trust_levels (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  insight_type VARCHAR NOT NULL,
  useful_count INTEGER DEFAULT 0,
  dismiss_count INTEGER DEFAULT 0,
  auto_mode BOOLEAN DEFAULT FALSE,
  auto_activated_at DATETIME,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);
CREATE UNIQUE INDEX idx_trust_user_type ON agent_trust_levels(user_id, insight_type);
```

### 전환 규칙

- `useful_count >= 5` → `auto_mode = true`, `auto_activated_at = now`
- Settings 페이지에서 수동으로 `auto_mode = false` 가능

## Auto Actions (Analyzer별)

| Analyzer | 안내 모드 (auto_mode: false) | 자동 모드 (auto_mode: true) |
|----------|---------------------------|--------------------------|
| PriceComparison | "평균 대비 20% 높습니다" 배너 | 과거 견적 3건 비교 테이블을 Comment로 자동 첨부 |
| SupplierRisk | "납기율 60%" 경고 | 대체 거래처 + 연락처를 Comment로 자동 첨부 |
| DueDateRisk | "D-3 위험도 critical" 알림 | 담당자에게 Notification 자동 발송 |
| CostSaving | "대체 거래처 15% 저렴" 안내 | 저렴한 거래처 견적을 OrderQuote에 자동 추가 |

## Service Architecture

```
CpoAgent::Service.analyze(order, user)
  ↓ Insight 생성 (기존과 동일)
  ↓
AgentTrustLevel.auto_mode?(user, insight_type)
  ├── false → 배너만 표시 (현재 동작)
  └── true  → CpoAgent::AutoActionService.execute(order, insight, user)
               ├── PriceComparison  → Comment 자동 첨부
               ├── SupplierRisk     → Comment 자동 첨부
               ├── DueDateRisk      → Notification 발송
               └── CostSaving       → OrderQuote 추가
               ↓
             사후 알림 Insight 생성 (severity: info, auto_action: true)
```

## AgentTrustLevel Model

```ruby
class AgentTrustLevel < ApplicationRecord
  belongs_to :user

  TRUST_THRESHOLD = 5

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

## AutoActionService

```ruby
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
      # 과거 견적 3건 비교 테이블을 Comment로 첨부
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
      # 대체 거래처 + 연락처를 Comment로 첨부
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
      # 담당자에게 Notification 발송
      assignees = @order.assignees.presence || [@user]
      assignees.each do |assignee|
        user = assignee.respond_to?(:user) ? assignee.user : assignee
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
      # 저렴한 거래처 견적을 OrderQuote에 자동 추가
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

## UI Changes

### 자동 처리 Insight 카드 스타일

기존 `_insight.html.erb`에 `auto_action` 분기 추가:
- `metadata["auto_action"] == true` → indigo 배경
- 접두사: "[CPO Agent 자동 처리]"
- 버튼: [확인] (dismiss만, 피드백 불필요)

### Settings 페이지 — Agent 자율 모드 관리

```
CPO Agent 설정
─────────────────────────────
단가 비교     [자동 ✅] 유용함 7회 (2026-03-15~)
거래처 리스크  [수동 ⬜] 유용함 2회
납기 위험     [자동 ✅] 유용함 5회 (2026-03-18~)
비용 절감     [수동 ⬜] 유용함 1회
─────────────────────────────
```

각 토글 클릭 시 `AgentTrustLevel#auto_mode` 업데이트.

## Feedback → Trust 연동

기존 `AgentInsightsController#feedback` 수정:

```ruby
def feedback
  insight = AgentInsight.find(params[:id])
  insight.update!(useful: params[:useful] == "true")

  # Trust Level 업데이트
  AgentTrustLevel.record_feedback!(
    user: current_user,
    insight_type: insight.insight_type,
    useful: insight.useful
  )

  # 자동 모드 전환 시 flash
  level = AgentTrustLevel.find_by(user: current_user, insight_type: insight.insight_type)
  if level&.auto_mode && level.useful_count == AgentTrustLevel::TRUST_THRESHOLD
    flash.now[:notice] = "이제부터 '#{insight.insight_type}' 유형은 CPO Agent가 자동 처리합니다"
  end

  # ... Turbo Stream 응답
end
```

## AgentInsightJob 수정

`perform(order_id)` → `perform(order_id, user_id)` 로 user 전달:

```ruby
def perform(order_id, user_id = nil)
  order = Order.includes(:supplier, :client, :order_quotes).find_by(id: order_id)
  user = User.find_by(id: user_id)
  return unless order

  insights = CpoAgent::Service.analyze(order)

  # 자동 모드 실행
  if user
    insights.each do |insight|
      CpoAgent::AutoActionService.execute(order, insight, user)
    end
  end
end
```

## Implementation Order

| # | File | Type | Description |
|---|------|------|-------------|
| 1 | `db/migrate/..._create_agent_trust_levels.rb` | Migration | 테이블 생성 |
| 2 | `app/models/agent_trust_level.rb` | Model | 신뢰 레벨 + 전환 로직 |
| 3 | `app/services/cpo_agent/auto_action_service.rb` | Service | 4개 자동 액션 |
| 4 | `app/controllers/agent_insights_controller.rb` | Modify | feedback에 trust 연동 |
| 5 | `app/services/cpo_agent/service.rb` | Modify | auto_mode 분기 |
| 6 | `app/jobs/agent_insight_job.rb` | Modify | user_id 전달 |
| 7 | `app/controllers/orders_controller.rb` | Modify | Job에 user_id 전달 |
| 8 | `app/views/agent_insights/_insight.html.erb` | Modify | 자동 처리 스타일 |
| 9 | Settings 페이지 Agent 토글 UI | View | 수동 ON/OFF |

## Out of Scope

- Claude AI 자연어 분석 (별도 Phase)
- GraphRAG 기반 맥락 인식 (Phase 3, 데이터 500건+ 축적 후)
- 자동 발주 생성 (승인 워크플로우 필요)
- 모바일 푸시 알림

## Future: Phase 3 — GraphRAG

데이터가 충분히 축적되면 (500건+):
- 품목-거래처-현장-시기 관계 그래프로 맥락 인식 비교
- 공급망 리스크 체인 추적
- 품목 유사도 기반 대체품 자동 발견
- InsureGraph Pro 기술 스택 재활용
