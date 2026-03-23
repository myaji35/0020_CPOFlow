# CPO Agent Supervisor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** LangGraph 기반 감독 레이어를 추가하여 CpoAgent 자동 액션에 사전 승인/거부/로깅 기능을 제공한다.

**Architecture:** 기존 Ruby Analyzer 4개는 변경 없이 유지. LangGraph(Python) FastAPI 서비스가 승인 워크플로우를 관리하고, Rails는 REST API로 통신. `/agent_supervisor` 독립 대시보드에서 승인 큐와 실행 로그를 관리.

**Tech Stack:** Ruby on Rails 8.1, Python 3.11+, LangGraph, FastAPI, SQLite3, Kamal, Docker

**Spec:** `docs/superpowers/specs/2026-03-23-cpo-agent-supervisor-design.md`

---

## File Structure

### Rails (신규 생성)
| File | Responsibility |
|------|----------------|
| `db/migrate/xxx_create_agent_executions.rb` | agent_executions 테이블 |
| `db/migrate/xxx_create_agent_policies.rb` | agent_policies 테이블 |
| `app/models/agent_execution.rb` | 실행 로그 모델 + enum + scopes |
| `app/models/agent_policy.rb` | 정책 모델 + lookup 메서드 |
| `app/services/cpo_agent/langgraph_client.rb` | LangGraph REST 호출 (타임아웃+재시도+fallback) |
| `app/controllers/agent_supervisor_controller.rb` | 대시보드 + 승인/거부/재시도 + 정책관리 |
| `app/controllers/webhooks/agent_supervisor_controller.rb` | LangGraph webhook 수신 (HMAC 검증) |
| `app/views/agent_supervisor/index.html.erb` | 대시보드 UI |
| `app/views/agent_supervisor/policies.html.erb` | 정책 관리 UI |
| `db/seeds/agent_policies.rb` | 기본 정책 시드 |

### Rails (수정)
| File | Change |
|------|--------|
| `app/jobs/agent_insight_job.rb` | Insight 생성 후 LangGraph evaluate 호출 추가 |
| `app/services/cpo_agent/auto_action_service.rb` | LangGraph resume 후 호출되는 방식으로 래핑 |
| `config/routes.rb` | agent_supervisor + webhook 라우트 추가 |
| `app/views/layouts/application.html.erb` | 좌측 내비게이션에 "Agent 감독" 메뉴 추가 |

### LangGraph Service (신규)
| File | Responsibility |
|------|----------------|
| `langgraph_service/Dockerfile` | Python 서비스 컨테이너 |
| `langgraph_service/requirements.txt` | 의존성 (langgraph, fastapi, uvicorn, httpx) |
| `langgraph_service/config.py` | 환경변수 설정 |
| `langgraph_service/main.py` | FastAPI 앱 + 3 endpoints |
| `langgraph_service/graph/state.py` | SupervisorState TypedDict |
| `langgraph_service/graph/nodes.py` | receive, check_policy, execute, log_result 노드 |
| `langgraph_service/graph/supervisor.py` | StateGraph 정의 |
| `langgraph_service/tests/test_graph.py` | 그래프 흐름 단위 테스트 |

---

## Task 1: Rails 데이터 모델 — agent_executions + agent_policies

**Files:**
- Create: `db/migrate/TIMESTAMP_create_agent_executions.rb`
- Create: `db/migrate/TIMESTAMP_create_agent_policies.rb`
- Create: `app/models/agent_execution.rb`
- Create: `app/models/agent_policy.rb`
- Create: `db/seeds/agent_policies.rb`
- Modify: `db/seeds.rb` (시드 로드 추가)

- [ ] **Step 1: agent_executions 마이그레이션 생성**

```bash
bin/rails generate migration CreateAgentExecutions
```

마이그레이션 파일 내용:
```ruby
class CreateAgentExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_executions do |t|
      t.references :order, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :agent_insight, foreign_key: true
      t.string  :insight_type, null: false
      t.string  :severity, null: false
      t.string  :action_type, null: false
      t.integer :status, default: 0, null: false
      t.string  :langgraph_thread_id
      t.text    :action_summary
      t.json    :metadata
      t.text    :reject_reason
      t.datetime :approved_at
      t.datetime :executed_at
      t.timestamps
    end

    add_index :agent_executions, :status
    add_index :agent_executions, [:order_id, :status]
    add_index :agent_executions, :langgraph_thread_id, unique: true
  end
end
```

- [ ] **Step 2: agent_policies 마이그레이션 생성**

```bash
bin/rails generate migration CreateAgentPolicies
```

```ruby
class CreateAgentPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_policies do |t|
      t.string  :insight_type, null: false
      t.string  :severity, null: false
      t.integer :approval_mode, default: 0, null: false
      t.integer :timeout_hours, default: 24
      t.integer :max_retries, default: 2
      t.timestamps
    end

    add_index :agent_policies, [:insight_type, :severity], unique: true
  end
end
```

- [ ] **Step 3: 마이그레이션 실행**

```bash
bin/rails db:migrate
```

- [ ] **Step 4: AgentExecution 모델 작성**

```ruby
# app/models/agent_execution.rb
class AgentExecution < ApplicationRecord
  belongs_to :order
  belongs_to :user, optional: true
  belongs_to :agent_insight, optional: true

  enum :status, {
    pending_approval: 0,
    approved: 1,
    executing: 2,
    completed: 3,
    rejected: 4,
    failed: 5,
    auto_executed: 6
  }

  scope :pending, -> { where(status: :pending_approval) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :recent, -> { order(created_at: :desc) }
  scope :needs_action, -> { where(status: [:pending_approval, :failed]) }

  def approvable?
    pending_approval?
  end

  def retriable?
    failed?
  end
end
```

- [ ] **Step 5: AgentPolicy 모델 작성**

```ruby
# app/models/agent_policy.rb
class AgentPolicy < ApplicationRecord
  enum :approval_mode, {
    require_approval: 0,
    auto_execute: 1,
    disabled: 2
  }

  validates :insight_type, presence: true
  validates :severity, presence: true
  validates :insight_type, uniqueness: { scope: :severity }

  def self.for(insight_type, severity)
    find_by(insight_type: insight_type, severity: severity) ||
      find_by(insight_type: "all", severity: severity) ||
      new(approval_mode: :require_approval)
  end
end
```

- [ ] **Step 6: 기본 정책 시드 작성**

```ruby
# db/seeds/agent_policies.rb
policies = [
  { insight_type: "price_comparison", severity: "alert",   approval_mode: :require_approval },
  { insight_type: "price_comparison", severity: "warning", approval_mode: :require_approval },
  { insight_type: "price_comparison", severity: "info",    approval_mode: :auto_execute },
  { insight_type: "supplier_risk",    severity: "alert",   approval_mode: :require_approval },
  { insight_type: "supplier_risk",    severity: "warning", approval_mode: :require_approval },
  { insight_type: "supplier_risk",    severity: "info",    approval_mode: :auto_execute },
  { insight_type: "due_date_risk",    severity: "alert",   approval_mode: :require_approval },
  { insight_type: "due_date_risk",    severity: "warning", approval_mode: :auto_execute },
  { insight_type: "due_date_risk",    severity: "info",    approval_mode: :auto_execute },
  { insight_type: "cost_saving",      severity: "alert",   approval_mode: :require_approval },
  { insight_type: "cost_saving",      severity: "warning", approval_mode: :require_approval },
  { insight_type: "cost_saving",      severity: "info",    approval_mode: :auto_execute },
]

policies.each do |attrs|
  AgentPolicy.find_or_create_by!(insight_type: attrs[:insight_type], severity: attrs[:severity]) do |p|
    p.approval_mode = attrs[:approval_mode]
  end
end
```

- [ ] **Step 7: 스모크 테스트**

```bash
bin/rails runner 'AgentExecution.count; AgentPolicy.count; puts "Models OK"'
```

- [ ] **Step 8: 커밋**

```bash
git add db/migrate/ app/models/agent_execution.rb app/models/agent_policy.rb db/seeds/ db/schema.rb
git commit -m "feat: AgentExecution + AgentPolicy 모델 — 감독 시스템 데이터 레이어"
```

---

## Task 2: LanggraphClient 서비스 — Rails → LangGraph 통신

**Files:**
- Create: `app/services/cpo_agent/langgraph_client.rb`

- [ ] **Step 1: LanggraphClient 작성**

```ruby
# app/services/cpo_agent/langgraph_client.rb
module CpoAgent
  class LanggraphClient
    TIMEOUT = 3 # seconds
    MAX_RETRIES = 1
    BASE_URL = ENV.fetch("LANGGRAPH_URL", "http://langgraph:8000")

    def self.evaluate(insight, order)
      new.evaluate(insight, order)
    end

    def self.resume(thread_id, decision:, user_id: nil, reason: nil)
      new.resume(thread_id, decision: decision, user_id: user_id, reason: reason)
    end

    def self.status(thread_id)
      new.status(thread_id)
    end

    def evaluate(insight, order)
      policy = AgentPolicy.for(insight.insight_type, insight.severity)
      payload = {
        order_id: order.id,
        insight_id: insight.id,
        insight_type: insight.insight_type,
        severity: insight.severity,
        action_type: action_type_for(insight),
        policy: policy.approval_mode,  # "require_approval" | "auto_execute" | "disabled"
        context: {
          title: insight.title,
          body: insight.body,
          metadata: insight.metadata
        }
      }
      post("/api/evaluate", payload)
    end

    def resume(thread_id, decision:, user_id: nil, reason: nil)
      payload = {
        thread_id: thread_id,
        decision: decision,
        user_id: user_id,
        reason: reason
      }
      post("/api/resume", payload)
    end

    def status(thread_id)
      get("/api/status/#{thread_id}")
    end

    private

    def post(path, payload)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = payload.to_json
      execute(uri, request)
    end

    def get(path)
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Get.new(uri)
      execute(uri, request)
    end

    def execute(uri, request, retries: 0)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      response = http.request(request)
      JSON.parse(response.body, symbolize_names: true)
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
      if retries < MAX_RETRIES
        Rails.logger.warn "[LanggraphClient] Retry #{retries + 1}: #{e.class}"
        execute(uri, request, retries: retries + 1)
      else
        Rails.logger.error "[LanggraphClient] Failed after #{MAX_RETRIES + 1} attempts: #{e.class} — #{e.message}"
        { error: true, message: e.message }
      end
    end

    def action_type_for(insight)
      case insight.insight_type
      when "price_comparison" then "auto_price_comparison"
      when "supplier_risk"    then "auto_supplier_risk"
      when "due_date_risk"    then "auto_due_date_notification"
      when "cost_saving"      then "auto_cost_saving"
      end
    end
  end
end
```

- [ ] **Step 2: 스모크 테스트**

```bash
bin/rails runner 'puts CpoAgent::LanggraphClient::BASE_URL; puts "Client loaded OK"'
```

- [ ] **Step 3: 커밋**

```bash
git add app/services/cpo_agent/langgraph_client.rb
git commit -m "feat: LanggraphClient — Rails→LangGraph REST 통신 (타임아웃+재시도)"
```

---

## Task 3: AgentInsightJob 수정 — LangGraph 연동

**Files:**
- Modify: `app/jobs/agent_insight_job.rb`

- [ ] **Step 1: AgentInsightJob에 LangGraph 평가 요청 추가**

기존 `agent_insight_job.rb`의 `perform` 메서드에서 **기존 `AutoActionService.execute` 호출 부분을 교체**한다. 기존 코드(직접 AutoAction 실행)를 LangGraph 경유로 변경하여 이중 실행을 방지한다.

**교체 대상** (기존 코드 line ~18-21):
```ruby
# 기존: auto_mode이면 직접 실행 — 이 부분을 아래로 교체
if trust_level&.auto_mode
  CpoAgent::AutoActionService.execute(order, insight, user)
end
```

**교체 후:**
```ruby
# LangGraph 감독 시스템 경유 실행
policy = AgentPolicy.for(insight.insight_type, insight.severity)

if policy.disabled?
  Rails.logger.info "[AgentInsightJob] Policy disabled for #{insight.insight_type}/#{insight.severity}"
  next
end

result = CpoAgent::LanggraphClient.evaluate(insight, order)

if result[:error]
  # LangGraph 불가 시 fallback: 기존 방식으로 직접 실행
  Rails.logger.warn "[AgentInsightJob] LangGraph unavailable, fallback to direct execution"
  trust_level = user.agent_trust_levels.find_by(insight_type: insight.insight_type)
  if trust_level&.auto_mode
    CpoAgent::AutoActionService.execute(order, insight, user)
  end
  next
end

AgentExecution.create!(
  order: order,
  agent_insight: insight,
  insight_type: insight.insight_type,
  severity: insight.severity,
  action_type: CpoAgent::LanggraphClient.new.send(:action_type_for, insight),
  status: result[:status] == "auto_executed" ? :auto_executed : :pending_approval,
  langgraph_thread_id: result[:thread_id]
)
```

- [ ] **Step 2: 스모크 테스트**

```bash
bin/rails runner 'puts AgentInsightJob.instance_methods(false).inspect; puts "Job OK"'
```

- [ ] **Step 3: 커밋**

```bash
git add app/jobs/agent_insight_job.rb
git commit -m "feat: AgentInsightJob에 LangGraph 감독 연동 + fallback"
```

---

## Task 4: Webhook 수신 컨트롤러 — HMAC 검증

**Files:**
- Create: `app/controllers/webhooks/agent_supervisor_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Webhook 컨트롤러 작성**

```ruby
# app/controllers/webhooks/agent_supervisor_controller.rb
module Webhooks
  class AgentSupervisorController < ActionController::API
    before_action :verify_signature

    def receive
      event = params[:event]
      thread_id = params[:thread_id]

      execution = AgentExecution.find_by(langgraph_thread_id: thread_id)
      unless execution
        Rails.logger.warn "[Webhook] Unknown thread_id: #{thread_id}"
        return head :not_found
      end

      case event
      when "approval_required"
        execution.update!(status: :pending_approval, action_summary: params[:action_summary])
        # 관리자에게 알림 생성
        Notification.create!(
          user: User.where(role: :admin).first,
          title: "Agent 승인 필요",
          body: "#{execution.insight_type} — #{params[:action_summary]}",
          url: "/agent_supervisor"
        ) if defined?(Notification)

      when "execution_completed"
        execution.update!(
          status: :completed,
          executed_at: Time.current,
          action_summary: params.dig(:result, :summary),
          metadata: params[:result]
        )

      when "execution_failed"
        execution.update!(
          status: :failed,
          metadata: { error: params[:error] }
        )
      end

      head :ok
    end

    private

    def verify_signature
      secret = Rails.application.credentials.dig(:langgraph, :webhook_secret)
      return if secret.blank? # 개발 환경에서는 스킵

      signature = request.headers["X-Webhook-Signature"]
      body = request.body.read
      request.body.rewind

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      unless ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
        Rails.logger.warn "[Webhook] Invalid signature"
        head :unauthorized
      end
    end
  end
end
```

- [ ] **Step 2: 라우트 추가**

`config/routes.rb`에 추가:
```ruby
# Webhook (인증 불필요 — HMAC 검증)
post "webhooks/agent_supervisor", to: "webhooks/agent_supervisor#receive"
```

- [ ] **Step 3: 스모크 테스트**

```bash
bin/rails routes | grep webhook
```
Expected: `POST /webhooks/agent_supervisor`

- [ ] **Step 4: 커밋**

```bash
git add app/controllers/webhooks/ config/routes.rb
git commit -m "feat: Webhook 수신 컨트롤러 — HMAC 검증 + 이벤트 처리"
```

---

## Task 5: Agent Supervisor 대시보드 컨트롤러 + 라우트

**Files:**
- Create: `app/controllers/agent_supervisor_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: 컨트롤러 작성**

```ruby
# app/controllers/agent_supervisor_controller.rb
class AgentSupervisorController < ApplicationController
  before_action :require_admin

  def index
    @pending = AgentExecution.pending.includes(:order, :agent_insight).recent
    @executions = AgentExecution.where.not(status: :pending_approval)
                               .includes(:order, :user).recent.limit(50)
    @stats = {
      pending_count: AgentExecution.pending.count,
      today_count: AgentExecution.today.count,
      today_auto: AgentExecution.today.auto_executed.count,
      today_approved: AgentExecution.today.where(status: [:approved, :completed]).count,
      approval_rate: calculate_approval_rate,
      failed_count: AgentExecution.failed.count
    }
  end

  def approve
    execution = AgentExecution.find(params[:id])
    return head :unprocessable_entity unless execution.approvable?

    execution.update!(status: :approved, user: current_user, approved_at: Time.current)

    # LangGraph resume
    result = CpoAgent::LanggraphClient.resume(
      execution.langgraph_thread_id,
      decision: "approved",
      user_id: current_user.id
    )

    if result[:error]
      # LangGraph 불가 시 직접 실행
      CpoAgent::AutoActionService.execute(execution.order, execution.agent_insight, current_user)
      execution.update!(status: :completed, executed_at: Time.current, action_summary: "Fallback 직접 실행")
    end

    redirect_to agent_supervisor_path, notice: "승인 완료 — 실행 중"
  end

  def reject
    execution = AgentExecution.find(params[:id])
    return head :unprocessable_entity unless execution.approvable?

    execution.update!(
      status: :rejected,
      user: current_user,
      reject_reason: params[:reason]
    )

    CpoAgent::LanggraphClient.resume(
      execution.langgraph_thread_id,
      decision: "rejected",
      user_id: current_user.id,
      reason: params[:reason]
    )

    redirect_to agent_supervisor_path, notice: "거부됨"
  end

  def retry_execution
    execution = AgentExecution.find(params[:id])
    return head :unprocessable_entity unless execution.retriable?

    result = CpoAgent::LanggraphClient.evaluate(execution.agent_insight, execution.order)
    execution.update!(status: :pending_approval, langgraph_thread_id: result[:thread_id])

    redirect_to agent_supervisor_path, notice: "재시도 요청됨"
  end

  def policies
    @policies = AgentPolicy.order(:insight_type, :severity)
  end

  def update_policies
    params[:policies].each do |id, attrs|
      AgentPolicy.find(id).update!(approval_mode: attrs[:approval_mode])
    end
    redirect_to policies_agent_supervisor_path, notice: "정책 업데이트됨"
  end

  private

  def require_admin
    redirect_to root_path, alert: "관리자만 접근 가능" unless current_user&.admin?
  end

  def calculate_approval_rate
    total = AgentExecution.where("created_at > ?", 30.days.ago)
                          .where(status: [:completed, :rejected]).count
    return 0 if total.zero?
    approved = AgentExecution.where("created_at > ?", 30.days.ago)
                             .where(status: :completed).count
    (approved.to_f / total * 100).round
  end
end
```

- [ ] **Step 2: 라우트 추가**

```ruby
# config/routes.rb에 추가
get  "agent_supervisor",                  to: "agent_supervisor#index"
patch "agent_supervisor/:id/approve",     to: "agent_supervisor#approve",       as: :approve_agent_execution
patch "agent_supervisor/:id/reject",      to: "agent_supervisor#reject",        as: :reject_agent_execution
patch "agent_supervisor/:id/retry",       to: "agent_supervisor#retry_execution", as: :retry_agent_execution
get   "agent_supervisor/policies",        to: "agent_supervisor#policies",      as: :policies_agent_supervisor
patch "agent_supervisor/policies/update", to: "agent_supervisor#update_policies", as: :update_policies_agent_supervisor
```

- [ ] **Step 3: 스모크 테스트**

```bash
bin/rails routes | grep agent_supervisor
```

- [ ] **Step 4: 커밋**

```bash
git add app/controllers/agent_supervisor_controller.rb config/routes.rb
git commit -m "feat: AgentSupervisor 컨트롤러 — 승인/거부/재시도/정책관리"
```

---

## Task 6: Agent Supervisor 대시보드 UI

**Files:**
- Create: `app/views/agent_supervisor/index.html.erb`
- Create: `app/views/agent_supervisor/policies.html.erb`
- Modify: `app/views/layouts/application.html.erb` (내비게이션 메뉴 추가)

- [ ] **Step 1: index.html.erb — KPI 바 + 승인 큐 + 실행 로그**

스펙의 Dashboard UI 섹션 목업 기반으로 구현. SLDS 스타일 준수:
- 상단 KPI 4칸 (승인대기/오늘실행/승인율/실패)
- 승인 대기 큐 (severity별 색상, 인라인 승인/거부 버튼)
- 실행 로그 테이블 (시간/Order/유형/상태/승인자)
- Tailwind CDN 스타일 (기존 앱과 동일)

- [ ] **Step 2: policies.html.erb — 정책 매트릭스 토글**

insight_type × severity 매트릭스 테이블:
- 각 셀에 require_approval / auto_execute / disabled 선택 드롭다운
- 저장 버튼 → update_policies 액션

- [ ] **Step 3: 좌측 내비게이션에 메뉴 추가**

`application.html.erb`에 admin 전용 "Agent 감독" 메뉴 추가:
```erb
<% if current_user&.admin? %>
  <li><a href="/agent_supervisor">Agent 감독</a></li>
<% end %>
```

- [ ] **Step 4: 브라우저 검증**

http://localhost:3000/agent_supervisor 접속하여 UI 확인

- [ ] **Step 5: 커밋**

```bash
git add app/views/agent_supervisor/ app/views/layouts/application.html.erb
git commit -m "feat: Agent Supervisor 대시보드 UI — KPI + 승인큐 + 로그 + 정책관리"
```

---

## Task 7: LangGraph Python 서비스 — 프로젝트 셋업

**Files:**
- Create: `langgraph_service/Dockerfile`
- Create: `langgraph_service/requirements.txt`
- Create: `langgraph_service/config.py`
- Create: `langgraph_service/graph/state.py`

- [ ] **Step 1: requirements.txt**

```
langgraph>=0.2.0
langgraph-checkpoint-sqlite>=1.0.0
fastapi>=0.110.0
uvicorn>=0.27.0
httpx>=0.27.0
pydantic>=2.6.0
```

- [ ] **Step 2: config.py**

```python
import os

RAILS_WEBHOOK_URL = os.getenv("RAILS_WEBHOOK_URL", "http://localhost:3000/webhooks/agent_supervisor")
WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")
CHECKPOINT_DIR = os.getenv("CHECKPOINT_DIR", "/tmp/langgraph_checkpoints")
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))
```

- [ ] **Step 3: state.py**

```python
from typing import TypedDict, Optional

class SupervisorState(TypedDict):
    order_id: int
    insight_id: int
    insight_type: str
    severity: str
    action_type: str
    context: dict
    policy: str           # "auto_execute" | "require_approval" | "disabled"
    decision: Optional[str]  # "approved" | "rejected"
    decision_by: Optional[int]
    result: Optional[dict]
    error: Optional[str]
```

- [ ] **Step 4: Dockerfile**

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 5: 커밋**

```bash
git add langgraph_service/
git commit -m "feat: LangGraph 서비스 프로젝트 셋업 — Dockerfile + config + state"
```

---

## Task 8: LangGraph 그래프 정의 — nodes.py + supervisor.py

**Files:**
- Create: `langgraph_service/graph/nodes.py`
- Create: `langgraph_service/graph/supervisor.py`

- [ ] **Step 1: nodes.py — 4개 노드 함수**

```python
import httpx
import hmac
import hashlib
import json
from config import RAILS_WEBHOOK_URL, WEBHOOK_SECRET

def receive(state: dict) -> dict:
    """입력 검증 및 초기 상태 설정"""
    return state

def check_policy(state: dict) -> dict:
    """정책 확인 — Rails에서 이미 policy를 전달받음"""
    return state

def route_by_policy(state: dict) -> str:
    """조건부 분기: auto_execute | require_approval | disabled"""
    return state.get("policy", "require_approval")

def send_webhook(event: str, data: dict):
    """Rails에 webhook 전송 (HMAC 서명 포함)"""
    payload = json.dumps({**data, "event": event})
    headers = {"Content-Type": "application/json"}
    if WEBHOOK_SECRET:
        sig = hmac.new(WEBHOOK_SECRET.encode(), payload.encode(), hashlib.sha256).hexdigest()
        headers["X-Webhook-Signature"] = sig
    try:
        httpx.post(RAILS_WEBHOOK_URL, content=payload, headers=headers, timeout=5.0)
    except Exception as e:
        print(f"[Webhook] Failed: {e}")

def request_approval(state: dict) -> dict:
    """승인 요청 webhook 전송 + interrupt"""
    send_webhook("approval_required", {
        "thread_id": state.get("_thread_id", ""),
        "order_id": state["order_id"],
        "insight_type": state["insight_type"],
        "severity": state["severity"],
        "action_summary": state.get("context", {}).get("title", "")
    })
    return state

def route_by_decision(state: dict) -> str:
    """승인/거부 분기"""
    return state.get("decision", "rejected")

def execute_action(state: dict) -> dict:
    """Rails에 실행 완료 webhook"""
    send_webhook("execution_completed", {
        "thread_id": state.get("_thread_id", ""),
        "order_id": state["order_id"],
        "result": {"summary": f"{state['action_type']} executed", "insight_id": state["insight_id"]}
    })
    return {**state, "result": {"status": "completed"}}

def log_rejected(state: dict) -> dict:
    """거부 로그"""
    return {**state, "result": {"status": "rejected"}}

def log_disabled(state: dict) -> dict:
    """비활성화 로그"""
    return {**state, "result": {"status": "disabled"}}
```

- [ ] **Step 2: supervisor.py — StateGraph 정의**

```python
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
from graph.state import SupervisorState
from graph.nodes import (
    receive, check_policy, route_by_policy,
    request_approval, route_by_decision,
    execute_action, log_rejected, log_disabled
)
from config import CHECKPOINT_DIR

def build_graph():
    builder = StateGraph(SupervisorState)

    builder.add_node("receive", receive)
    builder.add_node("check_policy", check_policy)
    builder.add_node("request_approval", request_approval)
    builder.add_node("execute_action", execute_action)
    builder.add_node("log_rejected", log_rejected)
    builder.add_node("log_disabled", log_disabled)

    builder.set_entry_point("receive")
    builder.add_edge("receive", "check_policy")

    builder.add_conditional_edges("check_policy", route_by_policy, {
        "auto_execute": "execute_action",
        "require_approval": "request_approval",
        "disabled": "log_disabled"
    })

    # interrupt after request_approval — 승인 대기
    builder.add_conditional_edges("request_approval", route_by_decision, {
        "approved": "execute_action",
        "rejected": "log_rejected"
    })

    builder.add_edge("execute_action", END)
    builder.add_edge("log_rejected", END)
    builder.add_edge("log_disabled", END)

    checkpointer = SqliteSaver.from_conn_string(f"{CHECKPOINT_DIR}/checkpoints.db")
    return builder.compile(checkpointer=checkpointer, interrupt_after=["request_approval"])

graph = build_graph()
```

- [ ] **Step 3: 커밋**

```bash
git add langgraph_service/graph/
git commit -m "feat: LangGraph 감독 그래프 — nodes + supervisor (interrupt 기반 승인)"
```

---

## Task 9: LangGraph FastAPI 엔드포인트 — main.py

**Files:**
- Create: `langgraph_service/main.py`

- [ ] **Step 1: main.py 작성**

```python
import uuid
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Optional
from graph.supervisor import graph
from config import HOST, PORT

app = FastAPI(title="CPOFlow Agent Supervisor")

class EvaluateRequest(BaseModel):
    order_id: int
    insight_id: int
    insight_type: str
    severity: str
    action_type: str
    policy: str = "require_approval"  # "require_approval" | "auto_execute" | "disabled"
    context: dict = {}

class ResumeRequest(BaseModel):
    thread_id: str
    decision: str  # "approved" | "rejected"
    user_id: Optional[int] = None
    reason: Optional[str] = None

@app.post("/api/evaluate")
async def evaluate(req: EvaluateRequest):
    thread_id = f"lg-{uuid.uuid4().hex[:12]}"
    config = {"configurable": {"thread_id": thread_id}}

    initial_state = {
        "order_id": req.order_id,
        "insight_id": req.insight_id,
        "insight_type": req.insight_type,
        "severity": req.severity,
        "action_type": req.action_type,
        "context": req.context,
        "policy": req.policy,  # Rails에서 AgentPolicy 조회 후 전달
        "_thread_id": thread_id,
    }

    result = graph.invoke(initial_state, config)

    # interrupt된 경우 (승인 대기)
    state = graph.get_state(config)
    if state.next:
        return {"thread_id": thread_id, "status": "pending_approval"}

    return {"thread_id": thread_id, "status": "auto_executed", "result": result.get("result")}

@app.post("/api/resume")
async def resume(req: ResumeRequest):
    config = {"configurable": {"thread_id": req.thread_id}}

    # as_node 지정: interrupt된 노드(request_approval) 이후로 resume
    graph.update_state(config, {
        "decision": req.decision,
        "decision_by": req.user_id,
    }, as_node="request_approval")

    result = graph.invoke(None, config)

    return {"status": req.decision, "result": result.get("result")}

@app.get("/api/status/{thread_id}")
async def status(thread_id: str):
    config = {"configurable": {"thread_id": thread_id}}
    state = graph.get_state(config)

    if state.next:
        return {"status": "pending_approval", "next": list(state.next)}

    values = state.values
    result_status = values.get("result", {}).get("status", "unknown")
    return {"status": result_status, "values": values}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
```

- [ ] **Step 2: 로컬 테스트**

```bash
cd langgraph_service
pip install -r requirements.txt
python -c "from graph.supervisor import graph; print('Graph compiled OK')"
```

- [ ] **Step 3: 커밋**

```bash
git add langgraph_service/main.py
git commit -m "feat: LangGraph FastAPI — evaluate/resume/status 3 endpoints"
```

---

## Task 10: Kamal 배포 설정 + 통합 테스트

**Files:**
- Modify: `config/deploy.yml`
- Create: `langgraph_service/tests/test_graph.py`

- [ ] **Step 1: deploy.yml에 langgraph accessory 추가**

```yaml
accessories:
  langgraph:
    image: ghcr.io/myaji35/cpoflow-langgraph:latest
    host: 158.247.235.31
    port: 8100:8000
    env:
      RAILS_WEBHOOK_URL: http://cpoflow-web:3000/webhooks/agent_supervisor
      WEBHOOK_SECRET: $LANGGRAPH_WEBHOOK_SECRET  # Kamal secrets (.kamal/secrets)에서 관리
      CHECKPOINT_DIR: /data/checkpoints
    volumes:
      - langgraph_data:/data
```

- [ ] **Step 2: pytest 기본 테스트**

```python
# langgraph_service/tests/test_graph.py
from graph.supervisor import graph

def test_auto_execute_flow():
    config = {"configurable": {"thread_id": "test-auto-1"}}
    result = graph.invoke({
        "order_id": 1, "insight_id": 1,
        "insight_type": "price_comparison", "severity": "info",
        "action_type": "auto_price_comparison",
        "context": {}, "policy": "auto_execute",
        "_thread_id": "test-auto-1"
    }, config)
    assert result["result"]["status"] == "completed"

def test_approval_flow_interrupt():
    config = {"configurable": {"thread_id": "test-approval-1"}}
    result = graph.invoke({
        "order_id": 2, "insight_id": 2,
        "insight_type": "price_comparison", "severity": "alert",
        "action_type": "auto_price_comparison",
        "context": {}, "policy": "require_approval",
        "_thread_id": "test-approval-1"
    }, config)
    state = graph.get_state(config)
    assert len(state.next) > 0  # interrupted

def test_disabled_flow():
    config = {"configurable": {"thread_id": "test-disabled-1"}}
    result = graph.invoke({
        "order_id": 3, "insight_id": 3,
        "insight_type": "cost_saving", "severity": "info",
        "action_type": "auto_cost_saving",
        "context": {}, "policy": "disabled",
        "_thread_id": "test-disabled-1"
    }, config)
    assert result["result"]["status"] == "disabled"
```

- [ ] **Step 3: 테스트 실행**

```bash
cd langgraph_service && python -m pytest tests/ -v
```

- [ ] **Step 4: Rails 마이그레이션 + 시드 배포**

```bash
kamal deploy
kamal app exec --reuse "bin/rails db:migrate"
kamal app exec --reuse "bin/rails runner 'load \"db/seeds/agent_policies.rb\"'"
```

- [ ] **Step 5: E2E 검증**

프로덕션에서 `/agent_supervisor` 접속 확인, KPI 표시 확인

- [ ] **Step 6: 최종 커밋**

```bash
git add config/deploy.yml langgraph_service/tests/
git commit -m "feat: Kamal 배포 설정 + LangGraph pytest + E2E 검증"
```
