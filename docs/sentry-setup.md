# Sentry 무료 플랜 설정 가이드

## 1. 가입 (5분)

1. https://sentry.io/signup/ 접속
2. GitHub/Google 계정으로 로그인 (대표님 계정)
3. 조직 이름: `Gagahoho` 또는 `AtoZ2010`
4. 프로젝트 생성:
   - Platform: **Ruby on Rails**
   - Project name: `cpoflow`
   - Alert frequency: **즉시 (every error)** — 클라이언트보다 먼저 알아야 함

## 2. DSN 발급

프로젝트 생성 직후 화면에서 자동 표시됨:
```
https://abc123def456@o111111.ingest.sentry.io/9999999
```

이 URL 복사.

## 3. 프로덕션 등록

```bash
# .kamal/secrets에 SENTRY_DSN 값 입력
# (대표님 직접 — 시크릿이라 Claude가 직접 못 함)
$ vi .kamal/secrets
# SENTRY_DSN=https://abc123def456@o111111.ingest.sentry.io/9999999

# 배포 (안전 배포 래퍼 사용)
$ bin/safe-deploy
```

## 4. 동작 확인

```bash
# prod 컨테이너에 들어가서 의도적 에러 발생
$ kamal app exec --reuse "bin/rails runner 'raise \"Sentry test\"'"

# Sentry 대시보드(https://sentry.io)에서 1분 안에 이벤트 확인
```

## 5. Slack 알림 통합 (권장)

1. Sentry 대시보드 → Settings → Integrations → Slack
2. Slack workspace 연결
3. Alert Rule 생성:
   - Trigger: 새 에러 발생 시
   - Frequency: 즉시
   - Channel: `#cpoflow-alerts` (또는 사장님 DM)

## 6. 알림 규칙 권장 설정

| 규칙 | 액션 | 효과 |
|---|---|---|
| 새 에러 발생 | Slack 즉시 | 1분 안에 인지 |
| 같은 에러 5분 10회 이상 | Slack 강조 알림 | 위급 상황 인지 |
| 에러 영향 사용자 5명+ | Slack 긴급 | 광범위 영향 인지 |

## 무료 플랜 한도 (참고)

| 항목 | 한도 |
|---|---|
| 에러 이벤트 | 5,000/월 |
| 성능 트랜잭션 | 10,000/월 |
| 세션 리플레이 | 50/월 |
| 보관 기간 | 30일 |
| 멤버 | 1명 |

CPOFlow 트래픽(사용자 5~10명) 기준 **5%도 안 쓸 것**.

## 비용 발생 시점

- 사용자 100명+ 됐을 때
- 에러 5,000/월 초과 (Sentry가 "Quota Exceeded" 알림 보냄, 자동 결재 안 됨)
- Team 플랜 업그레이드 시 $26/월
