# 비즈니스 로직 점검 통합 보고서 — 2026-04-22

## 요약

| 축 | 이슈 | 점수/커버리지 | CRITICAL |
|---|---|---|---|
| 도메인 규칙 | ISS-232 | 엔티티 13 / 규칙 23 / 시나리오 12 | 6건 (P0: 3건) |
| 뷰 구조 | ISS-233 | 라우트-뷰 79/79 정상 | 5건 (가독성) |
| 사용자 여정 | ISS-234 | **23/40 (58%)** | 1건 (온보딩 부재) |
| 비즈니스 로직 | ISS-235 | **커버리지 42%** (21/50) | 3건 (브랜치/권한) |

---

## Top 3 CRITICAL (즉시 수정)

### 1. 크로스 브랜치 데이터 유출 (P0)
- **위치**: `orders_controller.rb:7` (`Order.all`), `kanban_controller.rb:140,172,247` (`Order.find`)
- **영향**: Seoul 사용자가 Abu Dhabi 주문 전체 열람·이동·병합 가능
- **조치**: ISS-237 FIX 이슈 생성 → `scoped_orders.find`로 교체

### 2. Order 삭제 권한 누락 (P0)
- **위치**: `orders_controller.rb#destroy` — `require_manager!` 없음
- **영향**: viewer/member가 주문 영구 삭제 가능
- **조치**: ISS-238 FIX 이슈 생성

### 3. AI API 비용 무제한 노출 (P0)
- **위치**: `inbox_controller.rb` translate/analyze_link/generate_reply
- **영향**: viewer 포함 전체 유저가 Claude API 비용 소모 가능
- **조치**: ISS-239 FIX 이슈 생성

---

## Major (P1) — 설계 수준 개선

1. **상태전이 제약 없음** — 9단계 칸반 임의 전이 허용 (Order 모델에 ALLOWED_TRANSITIONS)
2. **통화 혼재 집계** — AED/USD/KRW가 단순 합산되어 KPI 왜곡
3. **낙관적 락 미구현** — `lock_version` 없음, 동시 편집 시 덮어쓰기
4. **viewer 컨트롤러 가드 부재** — MenuPermission이 뷰에서만 체크됨

---

## 자동 생성된 FIX 이슈

| ID | Type | Priority | 담당 |
|---|---|---|---|
| ISS-237 | BIZ_FIX | P0 | agent-harness |
| ISS-238 | BIZ_FIX | P0 | agent-harness |
| ISS-239 | BIZ_FIX | P0 | agent-harness |
| ISS-240 | UX_FIX | P0 | ux-harness |
| ISS-241 | STYLE_FIX | P0 | agent-harness |

---

## 원본 보고서

- `docs/.harness/bizcheck-2026-04-22-domain.md`
- `docs/.harness/bizcheck-2026-04-22-view.md`
- `docs/.harness/bizcheck-2026-04-22-journey.md`
- `docs/.harness/bizcheck-2026-04-22-biz.md`
