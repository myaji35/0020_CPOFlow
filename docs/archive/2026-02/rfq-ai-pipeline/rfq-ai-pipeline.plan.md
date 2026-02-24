# Plan: RFQ AI Pipeline

## Overview
현재 키워드+LLM 단순 분류 방식을 넘어, 사용자 피드백 학습 + 자동 칸반 생성 + 답변 초안 작성까지 아우르는 AI-Native RFQ 처리 파이프라인 구축

## Problem Statement
- LLM이 RFQ 판단만 하고 끝 → 이후 UX 없음
- 오분류 시 사용자 수동 보정 후 학습 안 됨
- RFQ 확정 후 칸반 전환까지 불필요한 클릭 다수
- 발주처 이력/과거 거래 패턴을 전혀 활용 못 함

## Goals
1. **스마트 분류**: 확신(Auto-create) / 불확실(확인 요청) / 제외 3단계 판정
2. **피드백 루프**: 사용자 맞음/아님 → few-shot 패턴 학습
3. **자동 칸반 생성**: 발주처·품목·납기 자동 채움
4. **답변 초안 자동 생성**: 수신 확인 + 예상 회신일 초안
5. **담당자 자동 배정**: 발주처 이력 기반

## Scope

### In Scope
- `RfqDetectorService`: 3단계 판정 로직 (confirmed / uncertain / excluded)
- `LlmRfqAnalyzerService`: 프롬프트 강화 + 발주처 이력 컨텍스트 주입
- `RfqFeedbackService`: 사용자 피드백 저장 + few-shot 패턴 관리
- `RfqReplyDraftService`: 수신 확인 답변 초안 생성 (Gemini)
- Inbox UI: "확인 필요" 탭 + 맞음/아님 버튼 + 답변 초안 패널
- `rfq_feedbacks` 테이블: 피드백 누적 저장
- `EmailToOrderService`: confirmed 시 자동 칸반 생성 + 담당자 배정

### Out of Scope
- 이메일 자동 발송 (답변 초안 생성까지만, 실제 발송은 사용자)
- ML 모델 훈련 (few-shot prompt 방식으로 대체)

## User Stories
1. 동기화 후 "확인 필요" 이메일이 별도 탭에 표시된다
2. "RFQ 맞음" 클릭 → 즉시 칸반 카드 생성, 담당자 배정
3. "RFQ 아님" 클릭 → 제외 처리 + 패턴 학습
4. RFQ 확정 시 답변 초안(한/영/아랍) 자동 생성
5. 같은 발주처 이메일은 다음부터 더 높은 신뢰도로 감지

## Implementation Phases
1. **Phase A**: 3단계 판정 + DB 스키마 (rfq_feedbacks)
2. **Phase B**: Inbox UI "확인 필요" 탭 + 피드백 버튼
3. **Phase C**: 피드백 → few-shot 학습 반영
4. **Phase D**: 답변 초안 자동 생성 패널
5. **Phase E**: 발주처 이력 기반 담당자 자동 배정

## Success Metrics
- RFQ 감지 정확도: 현재 추정 70% → 목표 90%+
- 확인 필요 → 칸반 전환: 클릭 5회 → 1회
- 답변 초안 생성으로 첫 응답 시간 50% 단축
