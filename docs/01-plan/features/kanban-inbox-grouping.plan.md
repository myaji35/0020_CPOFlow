# Feature Plan: kanban-inbox-grouping

## Overview
칸반 보드 Inbox 컬럼에서 동일 `reference_no`를 가진 Order 카드들을 그룹화하여
대표 카드 1개 + 스레드 수 뱃지로 표시한다.

## Problem Statement
- Inbox 컬럼에 동일 발주번호(예: 6000009324) 카드가 8개 개별로 나열됨
- 팀원이 이미 처리 중인 건인지 즉시 파악 불가 → 중복 처리 위험
- 36개 카드 중 실제 신규 RFQ는 훨씬 적음 → 스크롤 피로

## Solution (Option A)
- `reference_no` 있는 그룹: 최신 Order 1개만 카드로 표시 + "스레드 N건" 뱃지
- `reference_no` 없는 단건: 기존과 동일
- 클릭 시 드로어 → "관련 스레드" 탭에서 전체 스레드 확인

## Scope
- 칸반 Inbox 컬럼만 적용 (reviewing, quoted 등 다른 컬럼은 변경 없음)
- 컨트롤러: KanbanController#index 쿼리 수정
- 뷰: `_card.html.erb` 스레드 뱃지 추가
- 카운트 배지: 그룹 대표 카드 수 기준으로 표시

## Acceptance Criteria
1. Inbox 컬럼에서 동일 reference_no 그룹은 대표 카드 1개만 표시
2. 대표 카드에 "스레드 N건" 뱃지 표시 (N >= 2)
3. 카드 클릭 시 드로어의 스레드 탭에서 전체 메일 확인 가능
4. 컬럼 카운트 배지: 그룹 수 기준
5. 드래그-드롭 이동 시 대표 카드의 Order만 이동 (정상 동작)
6. 필터(검색/담당자/우선순위) 정상 동작 유지

## Out of Scope
- reviewing 이후 컬럼 그룹핑 (별도 기획 필요)
- 그룹 내 개별 카드를 칸반에서 직접 관리하는 기능

## Timeline
Plan → Design → Do → Check: 당일 완료 목표
