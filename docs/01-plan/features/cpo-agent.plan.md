# Feature Plan: cpo-agent

## Overview
CPOFlow에 AI 기반 **CPO(Chief Procurement Officer) Agent**를 통합하여,
구매 의사결정을 실시간으로 보조하는 참모 시스템을 구축한다.

Agent는 기존 Order/Supplier/Client/Product 데이터를 분석하여
**견적 심사, 단가 비교, 리스크 경고, 비용 절감 기회**를 사용자에게 자연스럽게 전달한다.

## Problem Statement
- 구매 담당자가 견적서를 받아도 **과거 단가 이력과 비교하는 수작업** 필요
- 거래처 리스크(납기 지연, 클레임)를 **오더별로 수동 확인** 해야 함
- 묶음 발주, 대체 거래처 등 **비용 절감 기회**를 놓치고 있음
- RFQ AI Pipeline은 "이 메일이 RFQ인가?" 판정만 → 구매 **의사결정 보조는 없음**

## Solution: Rails 내장 비동기 Agent

### 핵심 원칙
> **"Agent는 조용한 참모, 시끄러운 알림봇이 아니다"**
> - 업무 흐름 중간에 끼어들되, 강제 중단은 Level 3(Alert)만
> - 나머지는 있으면 보고, 없어도 진행 가능한 형태

### 아키텍처
```
사용자 액션 (오더 열람 / 견적 작성 / 칸반 이동)
  ↓
Controller → AgentInsightJob.perform_later(order_id, trigger_type)
  ↓
Solid Queue Background Job
  ↓
CpoAgentService.analyze(order, trigger_type)
  ├── PriceComparisonAnalyzer   (단가 비교)
  ├── SupplierRiskAnalyzer      (거래처 리스크)
  ├── CostSavingAnalyzer        (비용 절감 기회)
  └── DueDateRiskAnalyzer       (납기 위험 감지)
  ↓
AgentInsight 레코드 저장
  ↓
Turbo Stream broadcast → UI 배너/위젯 삽입
```

### Agent 의견 전달 UX (3단계 강도)

| Level | 형태 | 색상 | 닫기 | 예시 |
|-------|------|------|------|------|
| 1 Info | 작은 텍스트 | 회색 | 자동 숨김 | "이 거래처 평균 납기 14일" |
| 2 Warning | 배너 | 노란색 | 수동 닫기 | "단가가 시세 대비 20% 높습니다" |
| 3 Alert | 배너+액션 | 빨간색 | 확인 필수 | "이 거래처 미결 클레임 있음" |

### 전달 위치

| 위치 | 트리거 | 용도 |
|------|--------|------|
| **오더 드로어 상단 배너** | 오더 열람 시 | 단가 비교, 리스크 경고 |
| **견적 폼 인라인 힌트** | 단가 입력 시 | 과거 평균 대비 알림 |
| **대시보드 Agent 위젯** | 페이지 로딩 시 | 오늘의 브리핑 (납기 위험, 비용 절감) |
| **칸반 단계 전환 시** | 상태 변경 시 | 전환 전 주의사항 |

## Scope

### Phase 1: 데이터 기반 분석 (Rule-based, AI 없음)
- `AgentInsight` 모델 생성
- `AgentInsightJob` (Solid Queue)
- `CpoAgentService` + 4개 Analyzer
  - **PriceComparisonAnalyzer**: OrderQuote 이력 기반 단가 비교
  - **SupplierRiskAnalyzer**: Supplier 납기 준수율 + 리스크 등급
  - **DueDateRiskAnalyzer**: 납기 D-day 기반 경고
  - **CostSavingAnalyzer**: 동일 품목 복수 거래처 비교
- 드로어 상단 배너 UI (Turbo Stream)
- 대시보드 Agent 브리핑 위젯

### Phase 2: Claude AI 분석 (확장)
- Claude Haiku API 연동 (자연어 분석 + 추천 문구 생성)
- 자연어 질의 ("이번 달 가장 비싼 발주 5건?")
- 사용자 피드백 루프 ([유용함] / [무시] 버튼)

### Phase 3: 자동화 (장기)
- 반복 발주 자동 제안
- 승인 워크플로우 연동
- 묶음 발주 자동 그룹핑

## 데이터 모델

### AgentInsight (신규)
```ruby
create_table :agent_insights do |t|
  t.references :order, null: false, foreign_key: true
  t.references :supplier, foreign_key: true
  t.string     :insight_type    # price_comparison, supplier_risk, due_date_risk, cost_saving
  t.integer    :severity, default: 0  # 0=info, 1=warning, 2=alert
  t.string     :title
  t.text       :body
  t.json       :metadata        # 분석 수치 데이터 (단가 차이, 비교 거래처 등)
  t.boolean    :dismissed, default: false  # 사용자가 무시함
  t.boolean    :useful, null: true         # 피드백 (true=유용, false=불필요, nil=미응답)
  t.datetime   :expires_at      # 자동 만료 시각
  t.timestamps
end
```

## 기존 코드 활용

| 기존 자산 | 재활용 방법 |
|-----------|------------|
| `RiskAssessmentJob` | DueDateRiskAnalyzer의 기반 로직 참조 |
| `RfqReplyDraftJob` | Agent Job 패턴 참조 (Solid Queue) |
| `OrderQuote` 모델 | PriceComparisonAnalyzer 데이터 소스 |
| `Supplier#risk_grade` | SupplierRiskAnalyzer 입력 |
| Turbo Stream 패턴 | 드로어/대시보드 실시간 삽입 |
| `RfqFeedback` | 피드백 루프 패턴 참조 |

## Acceptance Criteria

### Phase 1 (MVP)
1. 오더 드로어 열람 시 1~2초 내 Agent 배너 표시 (비동기)
2. 단가 비교: 동일 품목 과거 3건 평균 대비 ±15% 이상이면 Warning
3. 거래처 리스크: 납기 준수율 80% 미만이면 Alert
4. 납기 위험: D-3 이내 미납품 오더 Alert
5. 대시보드 Agent 브리핑: 오늘 기준 위험/기회 Top 5
6. [무시] 버튼 클릭 시 해당 Insight 숨김 처리
7. 페이지 로딩 속도 영향 없음 (비동기 Job + Turbo Stream)

### Phase 2 (확장)
8. Claude Haiku 기반 자연어 분석 코멘트 생성
9. 사용자 자연어 질의 응답
10. [유용함]/[무시] 피드백으로 알림 빈도 자동 조절

## Out of Scope
- 자동 발주 (Phase 3 — 승인 워크플로우 필요)
- 외부 시세 데이터 연동 (API 비용 문제)
- 모바일 푸시 알림
- 다국어 Agent 응답 (Phase 1은 한국어 개발환경 기준)

## Risk & Mitigation

| 리스크 | 대응 |
|--------|------|
| 데이터 부족 (OrderQuote 이력 < 3건) | 분석 불가 시 Insight 미생성 (빈 배너 없음) |
| Agent 알림 피로 | 3단계 강도 + 무시 버튼 + 피드백 학습 |
| Claude API 비용 | Phase 1은 Rule-based만, Phase 2에서 Haiku 최소 호출 |
| Job 처리 지연 | Solid Queue 우선순위 설정 + expires_at 자동 만료 |

## Timeline
- Phase 1 (Rule-based MVP): Plan → Design → Do → Check 완료 목표
- Phase 2 (Claude AI): Phase 1 운영 후 데이터 축적 확인 시 진행
