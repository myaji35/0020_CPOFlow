# Project State — 0020_CPOFlow

> 이 파일은 SessionStart에 자동 로드됩니다. 프로젝트의 살아있는 맥락입니다.
> Harness hook이 자동 갱신하며, 수동 편집도 허용됩니다.

## 1. 지금 만들고 있는 것
<!-- 한 문장으로. 대표님이 직접 작성하거나 product-manager가 갱신 -->
_(아직 정의되지 않음 — 'harness 시작'으로 FEATURE_PLAN을 만들어 주세요)_

## 2. 최근 결정사항 (최신순, 최대 20개)
<!-- DECISIONS_BEGIN -->
- **2026-04-15 12:15** — eCount OAPI 통합 + Admin 메뉴 3종 + Line Icons 폰트 수정 운영 배포 (commit f803e7f)
- **2026-04-15 09:10** — Phase 1 + 4개 구조 개혁 전파 (design-critic 강등, project-state 도입, 분류 의무, 검토 게이트, 자체점검)
<!-- DECISIONS_END -->

## 3. 미해결 질문
<!-- OPEN_QUESTIONS_BEGIN -->
- _(없음)_
<!-- OPEN_QUESTIONS_END -->

## 4. 다음 마일스톤
<!-- MILESTONES_BEGIN -->
- _(미정)_
<!-- MILESTONES_END -->

## 5. 최근 변경 이력 (git log, 자동 갱신)
<!-- GITLOG_BEGIN -->
- 2026-04-15 fix(ui): Line Icons CDN을 jsdelivr로 교체 + eCount 메뉴 3종 추가
- 2026-04-15 fix(perf+security): inbox prefetch 복원 + 칸반 lazy + 첨부 권한 가드
- 2026-04-15 chore(deploy): Kamal에 ECOUNT_* 시크릿 5종 등록
- 2026-04-15 feat(ecount-api): 품목 10,000건 실 DB 반영 + Admin 동기화 대시보드
- 2026-04-15 docs(ecount): 샘플 리딩 성공 보고서 — 10,000건 수신 검증
- 2026-04-15 docs(ecount): API 검증 신청서 명세 문서 — 대표님 수동 제출용
- 2026-04-15 feat(ecount-api): 테스트 인증키 연동 — SESSION_ID 발급 성공
- 2026-04-15 test(card-status): auto_assigner 엣지 케이스 3건 추가 — 5 → 8 runs
- 2026-04-15 fix(settings): '칸반 상태 관리' 카드 manager 권한 해제 — admin 블록 밖으로 분리
- 2026-04-15 fix(observability): 에러 삼킴 3건 → logger.warn로 가시화
- 2026-04-15 fix(card-status-ui): 가독성 절대 규칙 위반 6건 수정 — design-critic 재심 8.4/10
- 2026-04-14 test: Job 테스트 7개 추가 (커버리지 60.72%)
- 2026-04-14 test: CpoAgent::Service, AutoActionService, Gmail LLM/첨부파일 서비스 테스트 추가 (커버리지 59.13%)
- 2026-04-14 test: 모델 테스트 7개 추가 (커버리지 57.35%)
- 2026-04-14 test: EcountApi 서비스 및 SheetsService 테스트 추가 (커버리지 57.08%)
- 2026-04-14 test(coverage): 모델 테스트 8개 추가 — 783 runs / 0 failures
- 2026-04-14 test(coverage): 서비스 레이어 테스트 8개 추가 — 커버리지 52% → 54%
- 2026-04-14 test(coverage): Gmail 서비스 테스트 5개 추가 — 커버리지 49% → 52%
- 2026-04-14 Revert "feat(rfq): 견적성 이메일 판독 LLM을 Gemma 4 E4B 로컬로 전환"
- 2026-04-14 feat(inbox): 다중 체크 삭제 — Gmail Trash + archived 일괄 처리
- 2026-04-14 feat(inbox): 받은편지함 메일 삭제 — Gmail Trash 이동 + Order archived
- 2026-04-14 feat(card-status): orders.priority 컬럼 제거 — CardStatus 전환 완료
- 2026-04-14 fix(tests): 회귀 실패 14건 전수 치료 — 667/1223 GREEN
- 2026-04-14 feat(rfq): 견적성 이메일 판독 LLM을 Gemma 4 E4B 로컬로 전환
- 2026-04-14 feat(card-status): 일간 배치 Job + System 테스트
- 2026-04-14 feat(card-status): Settings UI — 리스트·인라인 rename·편집 모달·드래그 정렬
- 2026-04-14 feat(card-status): Settings CRUD + reorder + inline_rename 컨트롤러 (Task 7)
- 2026-04-14 feat(card-status): Gmail 파이프라인 priority 제거 → AutoAssigner로 일원화
- 2026-04-14 feat(card-status): 뷰·헬퍼·컨트롤러·서비스 priority → card_status 전환
- 2026-04-14 feat(card-status): Order 모델을 CardStatus FK 기반으로 전환 + 자동 배정 콜백
- 2026-04-14 feat(card-status): AutoAssigner 서비스 — 규칙 기반 자동 배정
- 2026-04-14 chore(card-status): PRESETS 상수 → local var (경고 제거)
- 2026-04-14 feat(card-status): orders.card_status_id 추가 + 프리셋 seed + 데이터 이관
- 2026-04-14 fix(card-status): deletable? 가드 제거 — Task 2 이후 테스트 활성화
- 2026-04-14 feat(card-status): CardStatus 모델 + 테이블 + 팔레트 상수 추가
- 2026-04-14 docs(plan): 칸반 카드 상태 범례 구현 플랜 (11 tasks)
- 2026-04-14 fix(gmail): 본문/첨부 Base64 이중 디코딩 전역 수정
- 2026-04-14 chore(credentials): Ariba 포털 접근 비밀번호 갱신
- 2026-04-14 docs(spec): 칸반 카드 상태 범례 커스터마이즈 설계안
- 2026-04-14 feat(inbox): 검색 UX 부분 갱신 + 쿼리 최적화 (B안)
- 2026-04-14 fix(gmail): 첨부파일 이중 Base64 디코딩 제거 — google-apis-gmail_v1 0.47+ 호환
- 2026-04-13 fix(security): 첨부파일 P0 보안 수정 — attach 권한 + HTML XSS 방어
- 2026-04-13 feat(inbox): 2-pane 이메일 상세보기 UI 복원
- 2026-04-13 fix(attachment): 파일 업로드 버그 수정 + freeView 미리보기 확장
- 2026-04-13 fix(ci): bundler-audit 취약점 경고 임시 허용
- 2026-04-13 fix(ci): RuboCop 전체 auto-fix + ._ 파일 제외 + Brakeman 허용
- 2026-04-13 fix(ci):
<!-- GITLOG_END -->

## 6. 살아있는 이슈 (READY/IN_PROGRESS, 자동 갱신)
<!-- ISSUES_BEGIN -->
- _(살아있는 이슈 없음 — 새 기획 필요)_
<!-- ISSUES_END -->

---
_마지막 갱신: 2026-04-15 12:15_
