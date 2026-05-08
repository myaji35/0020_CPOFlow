# Sentry 24h 모니터링 가이드 (배포 직후)

대상 배포: 500 안정화 + 로딩 지연 패키지 (commits 0c80168 ~ 541c1b1)
검증 기간: 배포 +24h 집중 모니터링, 이후 일상 리듬 전환

---

## 1. 첫 1시간 (배포 직후 — 가장 중요)

### 1.1 Sentry 대시보드 접속
- https://cpoflow.sentry.io (또는 가입 시 사용한 조직 URL)
- 좌측 Issues → Filter: `is:unresolved last_seen:-1h`

### 1.2 신호 (이게 보이면 문제)
| 패턴 | 의미 | 조치 |
|---|---|---|
| `ActiveRecord::StatementInvalid: ambiguous column` | 빠진 컨트롤러 발견 | 즉시 수정 + 재배포 |
| `Propshaft::MissingAssetError: tailwind.css` | 빌드 누락 | 컨테이너 들어가 수동 build |
| `NoMethodError` 급증 | 페르소나/effective_role 미적용 곳 발견 | 해당 view/controller 수정 |
| `Errno::EADDRINUSE` | Thruster 포트 충돌 | Dockerfile PORT 환경변수 재확인 |
| `BusyException` 빈도 ↑ | 큐 간격 완화 효과 부족 | recurring.yml 추가 완화 |

### 1.3 정상 신호 (이게 보여야 정상)
- `/inbox` 500이 0건 (이전 매일 10건+)
- 5xx 전체가 1시간 이내 0~2건 (봇 트래픽 제외)
- Performance 탭에서 `/dashboard` p50 < 1s, p95 < 3s
- Performance 탭에서 `/inbox` p50 < 500ms

---

## 2. 첫 24시간 (일별 리듬 형성)

### 2.1 1일 1회 체크 (오전 09:00 권장)
```
Sentry → Issues → Filter: is:unresolved last_seen:-24h
```

확인 항목:
1. **신규 이슈 0건이 목표** — 1건이라도 새 이슈 있으면 그날 안에 분류
2. **기존 이슈 재발 횟수**: 어제 대비 ↓ 추세인지
3. **Performance** → Web Vitals → LCP/FCP — 75th percentile이 1.5s 이하인지

### 2.2 비교 대상 (Before/After 측정)
배포 직전 베이스라인과 비교:
| 메트릭 | Before (배포 직전) | After 목표 (24h) |
|---|---|---|
| `/inbox` 일일 5xx | 10~12건 | **0건** |
| `BusyException` 일일 | 15~27건 | **5건 이하** |
| 모든 페이지 평균 TTFB | 1.6~1.8s | **0.5s 이하** |
| Tailwind CDN 다운로드 | 407KB/페이지 | **0KB** |

---

## 3. 주간 리듬 (1주차 ~ 4주차)

### 3.1 매주 월요일 09:00
- Sentry → Discover → 지난 7일 5xx 차트
- Performance → Slow transactions Top 10 — 회귀 감지

### 3.2 알림 채널 권장
- Sentry Settings → Integrations → **Slack #cpoflow-alerts** 또는 메일
- Alert Rule:
  - "새 이슈 첫 발생" → 즉시
  - "1시간 안에 동일 이슈 5회+" → 긴급
  - "10분 안에 5xx 10건+" → 즉시 (실시간 장애)

---

## 4. 이상 패턴별 대응 플레이북

### 4.1 ambiguous column 재발견
```bash
# 즉시 패치
git checkout main && git pull
# 해당 컨트롤러 수정 — 패턴: orders.created_at, hash form 등
bash .kamal/hooks/pre-deploy   # 게이트 통과 확인
git commit -am "fix(prod): ambiguous column 재발견 차단"
git push
bin/safe-deploy
```

### 4.2 Tailwind 스타일 깨짐 (특정 클래스만 미적용)
원인: tailwind.config.js의 content scan 범위 누락 또는 동적 클래스 미safelist.
```bash
# safelist에 패턴 추가
vi config/tailwind.config.js
# 빌드 확인
bundle exec rails tailwindcss:build
git commit -am "fix(tailwind): safelist 추가 — XX 클래스" && git push
bin/safe-deploy
```

### 4.3 Cytoscape 미로드 (Drawer Flow 빈 화면)
원인: unpkg.com 차단 또는 lazy load 실패.
```bash
# 브라우저 DevTools Network에서 cytoscape*.js 200 확인
# 실패 시 fallback CDN(jsdelivr) 추가:
# order_flow_controller.js의 loadCytoscape() inject URL 변경
```

### 4.4 BusyException 재발
```bash
# 더 완화
vi config/recurring.yml   # 6h → 12h
# 또는 SOLID_QUEUE_IN_PUMA=false로 별도 컨테이너 분리 (다음 단계)
```

---

## 5. 24h 후 보고 양식

```
━━━ CPOFlow 배포 +24h 안정화 보고 ━━━
배포 SHA: 541c1b1
배포 시각: YYYY-MM-DD HH:MM UTC

[5xx]
- /inbox: 0건 (이전 12건 대비 -100%) ✅
- 전체: N건 (봇 RoutingError 제외)
- 신규 이슈 종류: …

[Performance]
- /dashboard p50: XXXms (목표 1000ms 이하)
- /kanban p50: XXXms
- /inbox p50: XXXms

[DB lock]
- BusyException: N건 (이전 21건 평균)

[페르소나 콤보]
- 사용 횟수: N (admin 사용자)
- 오류 0건 ✅

[Action Items]
- 추가 패치 N건 (있으면)
- 다음 주 검토 항목: …
```

---

## 6. Rollback 트리거 (이 신호 보면 즉시 rollback)
1. 5xx 발생률 > 5% (정상은 < 0.1%)
2. /inbox /kanban /dashboard 중 하나라도 100% 5xx
3. 페르소나 전환이 권한 상승 일으킴 (보안 critical)

```bash
kamal rollback   # 직전 버전으로 즉시 복귀
```

post-deploy hook(`bin/canary`)이 5xx 검출 시 자동 rollback하므로 사람 개입 전에 복구됩니다.
