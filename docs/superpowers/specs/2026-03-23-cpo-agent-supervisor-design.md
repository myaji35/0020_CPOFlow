# CPO Agent Supervisor — Design Spec

## Overview

CPOFlow의 기존 CpoAgent 시스템(4개 분석기 + 자동 액션)에 **감독 레이어**를 추가한다. LangGraph(Python) 별도 서비스가 승인/거부/실행 흐름을 관리하고, Rails에 독립 `/agent_supervisor` 대시보드를 제공한다.

## Goals

1. 관리자가 Agent 자동 액션을 **사전 승인/거부** 가능
2. 모든 Agent 실행을 **로그로 추적** 가능
3. severity × insight_type별 **정책** 설정 가능 (자동/승인/비활성)
4. 기존 Ruby Analyzer 4개를 **변경 없이** 유지

## Non-Goals

- 새로운 Agent 유형 추가 (현재 4개 중심)
- LLM 기반 판단 노드 (향후 확장 가능하나 이번 범위 아님)
- 모바일 알림 (웹 대시보드 + 기존 Notification 활용)

## Architecture

### System Flow

```
Rails (Order 조회)
  → Solid Queue Job → Ruby Analyzer (4개) → Insight 생성
  → REST POST /api/evaluate → LangGraph Service
  → LangGraph: check_policy → auto_execute | interrupt
  → interrupt → webhook → Rails Notification → 관리자 확인
  → 관리자 승인 → REST POST /api/resume → LangGraph resume
  → execute → webhook → Rails에 결과 저장 + AgentExecution 업데이트
```

### Approach: LangGraph 감독 레이어만 (Approach B)

- 기존 Ruby Analyzer 4개 100% 재사용
- LangGraph는 승인 흐름만 처리 (경량)
- REST API 통신 (Vultr 단일 서버에 최적)
- LangGraph 체크포인팅으로 승인 대기 상태 영속화

## Data Model

### agent_executions (신규)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint PK | |
| order_id | FK → orders | 대상 오더 |
| user_id | FK → users (nullable) | 승인/거부한 사용자 |
| agent_insight_id | FK → agent_insights | 연결된 Insight |
| insight_type | string | price_comparison, supplier_risk, due_date_risk, cost_saving |
| severity | string | info, warning, alert |
| action_type | string | auto_price_comparison, auto_supplier_risk 등 |
| status | integer enum | pending_approval(0), approved(1), executing(2), completed(3), rejected(4), failed(5), auto_executed(6) |
| langgraph_thread_id | string (unique) | LangGraph 상태 추적 |
| action_summary | text | 실행 결과 요약 |
| metadata | json | LangGraph 응답 원본, 에러 등 |
| reject_reason | text | 거부 시 사유 |
| approved_at | datetime | |
| executed_at | datetime | |
| timestamps | | |

Indexes: `status`, `[order_id, status]`, `langgraph_thread_id` (unique)

### agent_policies (신규)

| Column | Type | Description |
|--------|------|-------------|
| id | bigint PK | |
| insight_type | string | price_comparison 등 또는 "all" |
| severity | string | alert, warning, info |
| approval_mode | integer enum | require_approval(0), auto_execute(1), disabled(2) |
| timeout_hours | integer (default: 24) | 승인 대기 타임아웃 |
| max_retries | integer (default: 2) | 실행 실패 시 재시도 |
| timestamps | | |

Unique index: `[insight_type, severity]`

### Default Policies

| insight_type | alert | warning | info |
|---|---|---|---|
| price_comparison | require_approval | require_approval | auto_execute |
| supplier_risk | require_approval | require_approval | auto_execute |
| due_date_risk | require_approval | auto_execute | auto_execute |
| cost_saving | require_approval | require_approval | auto_execute |

## LangGraph Service

### Directory Structure

```
langgraph_service/
├── Dockerfile
├── requirements.txt        # langgraph, fastapi, uvicorn, httpx
├── main.py                 # FastAPI entrypoint
├── config.py               # env config
└── graph/
    ├── state.py            # SupervisorState TypedDict
    ├── nodes.py            # receive, check_policy, execute, log_result
    └── supervisor.py       # StateGraph definition
```

### State Schema

```python
class SupervisorState(TypedDict):
    order_id: int
    insight_id: int
    insight_type: str
    severity: str
    action_type: str
    context: dict
    policy: str              # "auto_execute" | "require_approval" | "disabled"
    decision: Optional[str]  # "approved" | "rejected"
    decision_by: Optional[int]
    result: Optional[dict]
    error: Optional[str]
```

### Graph Flow

```
receive → check_policy → [conditional]
  → "auto_execute" → execute → log_result
  → "require_approval" → interrupt (+ webhook) → [resume] → [conditional]
      → "approved" → execute → log_result
      → "rejected" → log_result
  → "disabled" → log_result (no-op)
```

### API Endpoints

| Method | Path | Direction | Purpose |
|--------|------|-----------|---------|
| POST | /api/evaluate | Rails → LangGraph | Insight 평가 요청 |
| POST | /api/resume | Rails → LangGraph | 승인/거부 전달 |
| GET | /api/status/{thread_id} | Rails → LangGraph | 상태 조회 |

### Webhook Callbacks

| Event | Direction | Payload |
|-------|-----------|---------|
| approval_required | LangGraph → Rails | thread_id, order_id, insight_type, severity, action_summary |
| execution_completed | LangGraph → Rails | thread_id, order_id, result |
| execution_failed | LangGraph → Rails | thread_id, order_id, error |

## Rails Integration

### Modified Files

| File | Change |
|------|--------|
| `AgentInsightJob` | Insight 생성 후 LangGraph에 evaluate 요청 추가 |
| `CpoAgent::AutoActionService` | LangGraph에서 호출받아 실행하는 방식으로 변경 |
| `config/routes.rb` | `/agent_supervisor`, `/webhooks/agent_supervisor` 추가 |

### New Files

| File | Purpose |
|------|---------|
| `AgentExecution` model | 실행 로그 모델 |
| `AgentPolicy` model | 정책 설정 모델 |
| `AgentSupervisorController` | 대시보드 + 승인/거부 액션 |
| `Webhooks::AgentSupervisorController` | LangGraph webhook 수신 (HMAC 서명 검증 포함) |
| `CpoAgent::LanggraphClient` | LangGraph REST 호출 서비스 |

### Routes

```ruby
# 대시보드
get  "agent_supervisor",          to: "agent_supervisor#index"
# 승인/거부
patch "agent_supervisor/:id/approve", to: "agent_supervisor#approve"
patch "agent_supervisor/:id/reject",  to: "agent_supervisor#reject"
patch "agent_supervisor/:id/retry",   to: "agent_supervisor#retry"
# 정책 관리
get   "agent_supervisor/policies",       to: "agent_supervisor#policies"
patch "agent_supervisor/policies/update", to: "agent_supervisor#update_policies"
# Webhook
post "webhooks/agent_supervisor", to: "webhooks/agent_supervisor#receive"
```

## Dashboard UI

### Layout: `/agent_supervisor`

1. **KPI 바** (4칸): 승인 대기 | 오늘 실행 | 승인율(30일) | 실패
2. **승인 대기 큐**: severity별 색상, 인라인 승인/거부 버튼
3. **실행 로그 테이블**: 시간, Order, 유형, 상태, 승인자, 재시도 링크
4. **정책 관리 탭**: insight_type × severity 매트릭스 토글 (이번 scope 포함)

### Access Control

- admin 역할만 접근 가능
- 좌측 내비게이션에 "Agent 감독" 메뉴 추가

## Deployment

### Kamal 통합

```yaml
# config/deploy.yml accessories 추가
accessories:
  langgraph:
    image: ghcr.io/myaji35/cpoflow-langgraph:latest
    host: 158.247.235.31
    port: 8100:8000
    env:
      RAILS_WEBHOOK_URL: http://cpoflow-web:3000/webhooks/agent_supervisor
      CHECKPOINT_DIR: /data/checkpoints
    volumes:
      - langgraph_data:/data
```

Docker 네트워크 내부 통신: `http://langgraph:8000`

## Testing Strategy

1. LangGraph 서비스: pytest로 graph 흐름 단위 테스트
2. Rails 통합: `bin/rails runner`로 스모크 테스트
3. E2E: 프로덕션 배포 후 실제 Insight → 승인 → 실행 흐름 검증

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| LangGraph 서비스 다운 | Rails fallback — 기존 AutoAction 직접 실행 (감독 없이) |
| LangGraph 일시적 타임아웃 | LanggraphClient에서 3초 타임아웃 + 1회 재시도 후 fallback |
| Webhook 보안 | HMAC-SHA256 서명 검증 (shared secret via Rails credentials) |
| 승인 타임아웃 | agent_policies.timeout_hours 후 자동 거부 + 알림 |
| Vultr 메모리 부족 | LangGraph 컨테이너 256MB 제한, SQLite 체크포인트 |
