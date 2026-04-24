# Host Nginx 설정 (Kamal 앞단)

CPOFlow는 Vultr 서버에서 다음 경로로 요청을 받는다:

```
Internet → Cloudflare → Host Nginx(:80/:443) → kamal-proxy(:3030) → Rails app(:3000)
```

호스트 Nginx 설정 파일은 서버 `/etc/nginx/sites-enabled/cpoflow-ddtl` 에 배치되어 있다.
저장소는 **같은 내용의 복사본만 보관**한다 (서버 재설치/교체 시 재현용).

## ISS-276: 첨부 업로드 413 이슈

Nginx 기본 `client_max_body_size`는 1MB. 2026-04-22 (cb6e30c)에 서버에서 수동으로 `50m`로 올렸으나 **저장소에는 기록되어 있지 않아** 서버 교체 시 유실될 위험이 있었다.

이번 커밋에서 다음 파일을 기록:
- `config/nginx/cpoflow-ddtl.conf` — 서버에 배치할 설정의 정본

## 서버에 배포하는 방법

```bash
# 1) 최신 파일을 서버로 복사
scp config/nginx/cpoflow-ddtl.conf root@158.247.235.31:/etc/nginx/sites-enabled/cpoflow-ddtl

# 2) 문법 검증
ssh root@158.247.235.31 "nginx -t"

# 3) 리로드 (중단 없음)
ssh root@158.247.235.31 "systemctl reload nginx"
```

## ⚠️ HTTPS 블록 주의사항

certbot이 자동 생성한 HTTPS(443) 블록에도 반드시 `client_max_body_size 50m;`를 유지해야 한다. certbot이 덮어쓰거나 renewal 시 누락될 수 있으니, 설정 편집 후 반드시 큰 파일 업로드 테스트 실행.
