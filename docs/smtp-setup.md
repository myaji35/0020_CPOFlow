# Production SMTP 설정 가이드 (ISS-260)

## 문제
현재까지 `config/environments/production.rb`의 SMTP 블록이 주석 처리 + `default_url_options: host="example.com"` 상태라 **배포 환경에서 비밀번호 재설정 메일 및 알림 메일 발송 불능** 상태였다.

## 수정 내역 (커밋 포함)
- `config/environments/production.rb`
  - `default_url_options.host` → `cpoflow.ddtl.co.kr` (ENV `MAILER_HOST`로 재정의 가능)
  - SMTP 설정 블록 활성화 — ENV → Rails credentials → fallback 순 조회
  - SMTP credentials 없으면 `:test` delivery_method로 안전 fallback + 로그 경고
- `config/deploy.yml`
  - `env.secret`에 `SMTP_USER_NAME`, `SMTP_PASSWORD`, `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_DOMAIN` 추가
  - `env.clear`에 `MAILER_HOST: cpoflow.ddtl.co.kr` 고정

## 대표님이 해야 할 일 (1회성)

### 옵션 A. Kamal secrets 사용 (권장)
`.kamal/secrets` 파일에 다음 추가 (이 파일은 .gitignore):

```bash
# Gmail App Password 예시 (atozone.com Google Workspace 가정)
SMTP_USER_NAME=noreply@atozone.com
SMTP_PASSWORD=xxxx xxxx xxxx xxxx   # Google 계정 보안 > 앱 비밀번호로 발급
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_DOMAIN=atozone.com
```

그 후:
```
kamal env push
kamal app boot   # 또는 kamal deploy
```

### 옵션 B. Rails encrypted credentials 사용
```
EDITOR=vim bin/rails credentials:edit -e production
```
파일에 추가:
```yaml
smtp:
  user_name: noreply@atozone.com
  password: xxxxxxxxxxxx
  address: smtp.gmail.com
  port: 587
  domain: atozone.com
```

## SMTP Provider별 설정

### Gmail (Google Workspace)
1. https://myaccount.google.com/apppasswords 에서 앱 비밀번호 생성
2. 2단계 인증 필수
3. `SMTP_ADDRESS=smtp.gmail.com`, `SMTP_PORT=587`
4. 일일 500건 제한 — 서비스 메일이 많으면 SendGrid 권장

### SendGrid
1. https://app.sendgrid.com/settings/api_keys 에서 API Key 발급
2. `SMTP_USER_NAME=apikey` (literal 문자열), `SMTP_PASSWORD=<API Key>`
3. `SMTP_ADDRESS=smtp.sendgrid.net`, `SMTP_PORT=587`
4. 무료 tier: 100건/일 · Essentials $19.95/월 50k건

### AWS SES
1. IAM에서 SES SMTP credentials 생성
2. `SMTP_ADDRESS=email-smtp.<region>.amazonaws.com` (예: `email-smtp.ap-northeast-2.amazonaws.com`)
3. `SMTP_PORT=587`
4. $0.10 / 1,000건 (매우 저렴) · sandbox 탈출 승인 필요

## 검증 방법

### 배포 후 Rails console에서 확인
```bash
kamal app exec --interactive --reuse "bin/rails console"
```
```ruby
ActionMailer::Base.delivery_method
# => :smtp  (credentials 정상 주입 시) / :test (미설정 시)

ActionMailer::Base.smtp_settings
# => { user_name: "noreply@...", address: "smtp.gmail.com", ... }

# 테스트 발송
Devise::Mailer.reset_password_instructions(User.first, "dummy-token").deliver_now
```

### 로그 확인
```bash
kamal app logs --since 5m | grep -i "mailer\|smtp"
```

## 회귀 방지
- SMTP credentials가 누락되면 `:test` delivery_method로 fallback → 앱이 크래시하지 않음
- `Rails.logger.warn "[ISS-260] SMTP credentials 미설정 — ..."` 경고 출력
- 비밀번호 재설정 링크가 여전히 `example.com`으로 가지 않음 (`MAILER_HOST`로 해결)
