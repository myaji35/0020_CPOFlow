# Plan: CPOFlow 고도화 7대 기능

**Feature**: cpoflow-enhancement
**작성일**: 2026-02-22
**작성자**: Claude (AI Engineer)
**상태**: Draft

---

## 1. 배경 및 목적

CPOFlow는 현재 475건의 발주 데이터를 관리 중이며, **122건 납기 지연 / 93건 긴급** 상태이다.
운영 데이터가 충분히 쌓인 시점에서, 실무 생산성과 의사결정 속도를 높이는 고도화가 필요하다.

### 핵심 문제
1. 납기 위험을 사전에 인지할 수단이 없음 (수동 확인)
2. 견적서/발주서를 시스템에서 직접 생성 불가 (별도 작업)
3. 주문 다건 처리 시 하나씩 클릭해야 함 (비효율)
4. 여러 거래처 견적을 한 화면에서 비교 불가
5. 검색이 주문명/고객명에만 국한됨
6. 납기 위험도가 수동 우선순위에 의존
7. 경영진용 KPI 리포트 화면 없음
8. Google Chat 연동 없음 (중동 현지 팀 소통 수단)

---

## 2. 구현 기능 목록 (7+1)

### Feature 1: 견적/발주 PDF 문서 생성기
**목표**: Order 상세 화면에서 원클릭으로 PDF 문서 출력
**사용자**: 영업/구매 담당자 (주 3-5회)
**성공 기준**: 클릭 후 3초 내 PDF 다운로드, 회사 로고·양식 포함

### Feature 2: 알림 센터 + Google Chat 연동
**목표**: D-7/D-3/D-0 자동 알림 + Google Chat Webhook 발송
**사용자**: 전 팀원 (매일)
**성공 기준**:
- 납기 알림 이메일 자동 발송 (ActionMailer)
- Google Chat Space에 알림 메시지 발송
- 앱 내 알림 센터 (읽음/안읽음 배지)

### Feature 3: 주문 일괄 처리 (Bulk Actions)
**목표**: 체크박스 선택 후 상태변경·담당자배정·CSV 내보내기
**사용자**: 관리자/매니저 (주 1-2회)
**성공 기준**: 50건 일괄 상태변경 2초 내 완료

### Feature 4: 견적 비교표 (Multi-Supplier Quotes)
**목표**: 하나의 Order에 여러 거래처 견적 등록 후 비교 선택
**사용자**: 구매 담당자 (매 견적 단계)
**성공 기준**: 견적 등록·비교·확정 워크플로우 완성

### Feature 5: Command Palette (Cmd+K 통합검색)
**목표**: 키보드 단축키로 전체 데이터 즉시 검색
**사용자**: 전 팀원 (매일 수회)
**성공 기준**: 입력 후 300ms 내 결과 표시, 주문·발주처·거래처·직원 통합

### Feature 6: 납기 위험도 자동 계산
**목표**: 납기일·현재상태·진행속도 기반 위험도(🔴🟡🟢) 자동 산정
**사용자**: 전 팀원 (매일 자동)
**성공 기준**: 위험도 배지 칸반/목록 전체 표시, 배치 업데이트 1분 주기

### Feature 7: 경영 리포트 대시보드
**목표**: 월별 수주/납품/거래처별 KPI 경영진 전용 화면
**사용자**: 대표님/관리자 (주 1-2회)
**성공 기준**: 월별 트렌드, 거래처 비중, 직원 실적 한 화면에서 확인

---

## 3. 기술 스택 결정

| 기능 | 기술 | 비고 |
|------|------|------|
| PDF 생성 | `Grover` gem (Puppeteer 기반) 또는 `prawn` | HTML 템플릿 → PDF 변환 |
| 알림 이메일 | `ActionMailer` (기존) | NotificationJob 완성 |
| Google Chat | Google Chat Incoming Webhook | 설정만으로 연동 가능 |
| 앱 내 알림 | `Notification` 모델 + Turbo Stream | 실시간 배지 |
| Bulk Actions | Stimulus + Turbo Streams | 체크박스 선택 상태 관리 |
| 견적 비교 | `OrderQuote` 모델 추가 | Order hasMany OrderQuotes |
| Command Palette | Stimulus Controller + `/search` API | Cmd+K 트리거 |
| 위험도 | `risk_score` 컬럼 + `RiskAssessmentJob` | 매분 배치 계산 |
| 경영 리포트 | `/reports` 컨트롤러 + 기존 집계 쿼리 | Google Sheets 연동 활용 |

---

## 4. 데이터 모델 변경

### 신규 모델
```ruby
# 앱 내 알림
Notification: user_id, notifiable(polymorphic), title, body, read_at, notification_type

# 거래처 견적
OrderQuote: order_id, supplier_id, unit_price, currency, lead_time_days,
            validity_date, notes, selected(boolean), submitted_at
```

### 기존 모델 변경
```ruby
# Order 모델
add_column :orders, :risk_score, :integer, default: 0  # 0-100
add_column :orders, :risk_level, :string               # low/medium/high/critical
add_column :orders, :risk_updated_at, :datetime
```

---

## 5. 구현 우선순위 및 순서

```
Phase A (독립 구현 가능):
  ├── Feature 5: Command Palette (프론트엔드 전용, DB 변경 없음)
  ├── Feature 6: 위험도 자동 계산 (Order 컬럼 추가)
  └── Feature 7: 경영 리포트 (기존 데이터 집계)

Phase B (Phase A 완료 후):
  ├── Feature 2: 알림 센터 + Google Chat (Notification 모델 필요)
  ├── Feature 3: Bulk Actions (프론트엔드 + 기존 API 활용)
  └── Feature 1: PDF 문서 생성 (gem 설치 필요)

Phase C (Phase B 완료 후):
  └── Feature 4: 견적 비교표 (OrderQuote 모델 필요)
```

---

## 6. 비기능 요구사항

- **성능**: 목록 페이지 LCP 2초 이내 유지 (위험도 배지 추가 후에도)
- **권한**: Bulk Actions는 manager 이상만 가능, 경영 리포트는 admin만
- **모바일**: Command Palette는 모바일에서 하단 버튼으로 대체
- **알림 빈도**: 동일 Order에 대해 같은 날 중복 알림 없음

---

## 7. 제외 범위 (이번 구현에서 제외)

- WhatsApp API 연동 (Google Chat으로 대체)
- 모바일 PWA (별도 스프린트)
- 제품 카탈로그 재고 관리 (Phase 5)
- i18n 다국어 전환 (AR/EN, Phase 6)

---

## 8. 완료 기준 (Definition of Done)

- [ ] 7개 기능 모두 화면에서 동작 확인
- [ ] 기존 기능 회귀 없음 (주요 화면 Playwright 점검)
- [ ] Google Chat Webhook 테스트 메시지 발송 성공
- [ ] PDF 문서 실제 다운로드 및 내용 검증
- [ ] 위험도 배지 칸반·목록·상세 전체 표시
