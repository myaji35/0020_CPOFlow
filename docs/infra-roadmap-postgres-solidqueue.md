# 인프라 로드맵 — SQLite→PostgreSQL + SolidQueue 분리 검토

작성: 2026-05-08
대상: CPOFlow prod 안정화 다음 단계

---

## 1. 현재 상태 (병목 분석)

| 항목 | 현재 | 한계 |
|---|---|---|
| DB | SQLite WAL 단일 파일 | 동시 쓰기 1개, 락 경합 빈발 |
| Web | Puma 1 worker × 5 threads | GVL + SQLite 락이 실질 동시성 차단 |
| Queue | SolidQueue **Puma 안에서 동거** | recurring job → DB 락 → 사용자 요청에 전파 |
| Cache | SolidCache (별도 SQLite 파일) | OK |
| Cable | SolidCable (별도 SQLite 파일) | OK |
| Prod DB 크기 | 126MB (orders 누적) | SQLite는 GB 단위까지 OK, 락이 먼저 한계 |
| 운영 사례 | BusyException 일 15~27건 (배포 직전) | 6h 완화 후 감소 예상하나 근본 해결 X |

**근본 원인**: SolidQueue가 Puma와 같은 프로세스에서 도는 단일 SQLite를 두드림 → 1개 큐 작업이 사용자 요청 1개를 5초 블록.

---

## 2. 두 가지 개선 방향 (순서/병행 선택)

### 방향 A: SolidQueue 별도 컨테이너 분리 (난이도 ★, 효과 ★★)
**할 것**:
1. `config/deploy.yml`에 worker role 추가:
   ```yaml
   servers:
     web:
       hosts: [158.247.235.31]
     worker:
       hosts: [158.247.235.31]
       cmd: bin/jobs   # SolidQueue supervisor 단독 실행
   ```
2. `config/deploy.yml`의 `env.clear.SOLID_QUEUE_IN_PUMA` 제거
3. Puma는 사용자 요청만, worker 컨테이너가 큐만 처리 → **DB 락 경합은 여전**하지만 사용자 요청 timeout 빈도 ↓

**효과**:
- Puma 응답성 회복 (큐가 5초 잡아도 사용자 요청 안 막힘)
- worker가 죽어도 web은 살아 있음 (장애 격리)
- 메모리 +500MB ~ 1GB (워커 컨테이너)

**제약**:
- 같은 SQLite 파일을 web/worker 양쪽에서 두드림 → SQLite WAL은 다중 프로세스 OK이지만 쓰기 락은 여전
- BusyException 빈도 절반 정도 감소 예상 (큐 ↔ 큐 경합은 그대로)

**리스크**: 낮음. Kamal 표준 패턴, 롤백 쉬움 (volume 그대로).

**소요**: 30분 + 검증 1시간.

---

### 방향 B: PostgreSQL 마이그레이션 (난이도 ★★★, 효과 ★★★★)
**할 것**:
1. PostgreSQL 16 컨테이너 추가 (Vultr managed PG 또는 self-host)
2. `Gemfile`: `gem "sqlite3"` → `gem "pg"`
3. `config/database.yml` 4개 connection(primary/cache/queue/cable) 모두 PG 전환
   - 권장: 단일 PG instance + 4개 schema 또는 4개 DB
4. 데이터 마이그레이션:
   ```bash
   # 옵션 1: pgloader (자동, 1번에 끝)
   pgloader sqlite:///rails/storage/production.sqlite3 postgres://user:pw@host/cpoflow_prod
   # 옵션 2: rails 단계 (안전, 검증 가능)
   # primary만 먼저 → cache/queue/cable은 빈 상태 시작
   ```
5. SQLite-only SQL 호환성 점검:
   - `JULIANDAY(...)` → PG의 `EXTRACT(EPOCH FROM ...)/86400`
   - `date('now')` → `CURRENT_DATE`
   - `LIKE` 대소문자 — PG는 case-sensitive(SQLite는 case-insensitive 기본)
   - `NULLS LAST` — PG 지원 OK (이미 사용 중)

**효과**:
- **BusyException 완전 소멸** — PG는 row-level lock + MVCC
- Puma WEB_CONCURRENCY 4+로 안전하게 확장 가능 → 동시 사용자 30+ 처리
- Solid Queue도 worker 멀티 프로세스 안전
- async_query_executor 진짜 병렬 효과 (현재 SQLite는 직렬화)
- 백업/복구 표준화 (pg_dump)

**제약**:
- 인프라 비용 +$10~30/월 (Vultr managed PG 또는 self-host CPU)
- 마이그레이션 다운타임 30분 ~ 2시간 (DB 크기 + 검증)
- 기존 SQLite-specific SQL 8~15곳 패치 (점검 + 수정)

**리스크**: 중간. 단, 사전 staging 검증으로 통제 가능.

**소요**:
- 코드 변경: 1일
- 데이터 마이그레이션 + 검증: 0.5일
- 운영 모니터링 강화: 1주

---

## 3. 권고 단계 (안전한 순서)

### Phase 1: 즉시 — 방향 A (분리만)
- 1주차: worker 컨테이너 분리 + 1주 모니터링
- 효과: BusyException 50% 감소 + Puma 응답성 회복 (체감 즉각)
- 비용: 거의 0 (기존 서버에 컨테이너 1개 추가)

### Phase 2: 1개월 후 — PostgreSQL staging 검증
- 별도 staging 환경 구축 (Vultr +$10/월 신규 인스턴스)
- 실 데이터 복제 → 1주 dogfooding (대표님만 staging 사용)
- SQL 호환성 + 성능 비교

### Phase 3: 2개월 후 — PostgreSQL prod 전환
- 사전 통보(클라이언트) → 야간 30분 다운타임 → 전환
- 1주 close monitoring

### Phase 4: 3개월 후 — Puma WEB_CONCURRENCY 확장
- PG 안정화 후 워커 2~4개로 확장 → 동시 사용자 처리량 5배

---

## 4. 비용 비교 (월간)

| 옵션 | 추가 비용 | 효과 | ROI |
|---|---|---|---|
| 현 상태 유지 | $0 | 매일 5xx 1건+ → 클라이언트 신뢰 ↓ | -- |
| Phase 1 (worker 분리) | ~$0 | BusyException 50%↓ | 매우 높음 |
| Phase 2-3 (PG 마이그레이션) | $20~30/월 | 5xx 안정 + 동시성 5배 | 높음 |
| AWS RDS PG (참고) | $30~80/월 | 같은 효과 + 자동 백업/패치 | 중간 (Vultr보다 비쌈) |

---

## 5. 의사결정 매트릭스

**다음 조건이면 Phase 2 즉시 추진**:
- [ ] 동시 사용자 5명 이상 (현재 1~2명, kds@/박부장/직원)
- [ ] 클라이언트가 5xx를 다시 보고
- [ ] eCount API 동기화 빈도를 다시 줄이고 싶음 (지금 6h)
- [ ] 모바일/태블릿 사용 비중 증가 (병렬 요청 ↑)

**Phase 1만으로 충분한 조건**:
- [ ] 24h 모니터링에서 BusyException 5건 이하
- [ ] /inbox 5xx가 0건 유지
- [ ] Sentry 신규 이슈 < 1건/일

---

## 6. 즉시 실행 가능한 다음 작업 (요청 시)

1. **Phase 1 적용 (worker 분리)** — 30분
   ```bash
   # config/deploy.yml에 worker role 추가
   # config/deploy.yml에서 SOLID_QUEUE_IN_PUMA 제거
   bin/safe-deploy
   ```
2. **PostgreSQL staging 환경 구축** — 1일
3. **SQLite-only SQL grep 보고서** — 30분 (Phase 2 사전 작업)

대표님이 어느 Phase부터 시작할지 지시하시면 즉시 착수.
