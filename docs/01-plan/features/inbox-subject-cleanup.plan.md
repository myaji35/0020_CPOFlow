# Plan: inbox-subject-cleanup — Inbox 메일 제목 간소화

**Feature**: inbox-subject-cleanup
**Created**: 2026-03-16
**Origin**: 2026.03.13 회의 안건 #1
**Phase**: Plan

---

## 1. 배경 및 목적

견적업무 특성상 동일 견적번호(Reference No.)에 대해 RE:/FW: 접두사가 반복 누적되어 Inbox 가독성이 심하게 저하됨.

**문제 사례:**
```
RE: RE: RE: FW: RFQ 6000009324 - Bosch Power Tools Set GBH 2-26 - 3rd Reminder
```

이미 `reference_no` 기준 그룹핑(히스토리) 기능이 구현되어 있으므로, 제목에서 중복 정보를 제거하고 핵심만 표시하면 업무 효율 향상.

## 2. 현재 구조 분석

### 2.1 데이터 흐름
```
Gmail API → gmail_service.rb (parse_message)
  → email_to_order_service.rb (build_title)
    → Order.original_email_subject (원본 그대로 저장)
    → Order.title (RFQ/ARIBA 접두사 추가)
```

### 2.2 관련 컬럼 (Order 모델)
| 컬럼 | 용도 | 현재 상태 |
|------|------|----------|
| `original_email_subject` | Gmail 원본 제목 | RE/FW 포함 그대로 저장 |
| `title` | 카드 표시용 제목 | `build_title()`로 생성 (RFQ/ARIBA 접두사) |
| `translated_subject` | AI 번역 제목 | Google Translate 결과 |
| `reference_no` | 견적번호 | 별도 필드로 이미 존재 |

### 2.3 제목 표시 위치 (총 10곳)
| 위치 | 파일 | 라인 |
|------|------|------|
| Inbox 목록 (스레드 내) | `inbox/index.html.erb` | 252 |
| Inbox 목록 (단건) | `inbox/index.html.erb` | 294 |
| Inbox 상세 (page_title) | `inbox/show.html.erb` | 2 |
| Inbox 상세 (h2) | `inbox/show.html.erb` | 14 |
| Inbox 상세 (h1) | `inbox/show.html.erb` | 27 |
| Inbox 상세 (관련 메일) | `inbox/show.html.erb` | 443 |
| Order 드로어 (원본) | `orders/_drawer_content.html.erb` | 270 |
| Order 드로어 (스레드 목록) | `orders/_drawer_content.html.erb` | 363, 386 |
| Inbox 검색 | `inbox_controller.rb` | 31 (LIKE 쿼리) |
| 발주번호 추출 | `orders_controller.rb` | 171 (regex) |

## 3. 구현 계획

### 3.1 Order 모델에 `display_subject` 메서드 추가

```ruby
# app/models/order.rb
def display_subject
  subject = original_email_subject.to_s.strip
  # 1. RE:/FW:/Fwd: 접두사 반복 제거
  subject = subject.gsub(/\A\s*(RE|FW|Fwd)\s*:\s*/i, '').strip while subject.match?(/\A\s*(RE|FW|Fwd)\s*:/i)
  # 2. reference_no가 있으면 제목에서 해당 번호 제거 (배지로 별도 표시)
  if reference_no.present?
    subject = subject.gsub(/\b#{Regexp.escape(reference_no)}\b\s*[-–—]?\s*/, '').strip
  end
  # 3. 앞뒤 구분자(-) 정리
  subject = subject.gsub(/\A[-–—\s]+|[-–—\s]+\z/, '').strip
  subject.presence || title
end
```

### 3.2 상태 키워드 태그 추출

```ruby
# app/models/order.rb
SUBJECT_TAGS = {
  /reminder/i    => "Reminder",
  /revised/i     => "Revised",
  /cancel/i      => "Cancelled",
  /urgent/i      => "Urgent",
  /update/i      => "Updated",
  /extend/i      => "Extended",
  /final/i       => "Final"
}.freeze

def subject_tags
  tags = []
  subject = original_email_subject.to_s
  SUBJECT_TAGS.each { |pattern, label| tags << label if subject.match?(pattern) }
  tags.uniq
end
```

### 3.3 뷰 변경 — `display_subject` 사용

**Before (10곳 동일 패턴):**
```erb
<%= order.original_email_subject.presence || order.title %>
```

**After:**
```erb
<% if order.reference_no.present? %>
  <span class="text-xs px-1.5 py-0.5 bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 rounded font-mono mr-1"><%= order.reference_no %></span>
<% end %>
<%= order.display_subject %>
<% order.subject_tags.each do |tag| %>
  <span class="text-xs px-1 py-0.5 bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 rounded ml-1"><%= tag %></span>
<% end %>
```

### 3.4 검색 호환성

- `inbox_controller.rb` LIKE 검색: `original_email_subject` 그대로 유지 (원본 기준 검색이 더 정확)
- `display_subject`는 **표시용 only** — DB 컬럼 추가 없음, 런타임 계산

### 3.5 build_title 개선 (신규 메일 수신 시)

`email_to_order_service.rb`의 `build_title` 메서드에도 RE/FW strip 적용:

```ruby
def build_title
  subject = @email[:subject].to_s.strip
  subject = subject.gsub(/\A\s*(RE|FW|Fwd)\s*:\s*/i, '').strip while subject.match?(/\A\s*(RE|FW|Fwd)\s*:/i)
  # ... 이하 기존 로직
end
```

## 4. 영향 범위

### 4.1 변경 파일 (총 5개)

| 파일 | 변경 내용 | 난이도 |
|------|----------|-------|
| `app/models/order.rb` | `display_subject`, `subject_tags` 메서드 추가 | **핵심** |
| `app/services/gmail/email_to_order_service.rb` | `build_title` RE/FW strip | 중 |
| `app/views/inbox/index.html.erb` | 제목 표시 2곳 변경 + 배지/태그 | 중 |
| `app/views/inbox/show.html.erb` | 제목 표시 4곳 변경 + 배지/태그 | 중 |
| `app/views/orders/_drawer_content.html.erb` | 제목 표시 3곳 변경 | 하 |

### 4.2 비변경 파일

| 파일 | 이유 |
|------|------|
| DB 마이그레이션 | 없음 (새 컬럼 추가 없음, 런타임 계산) |
| `inbox_controller.rb` | 검색은 `original_email_subject` 원본 유지 |
| `orders_controller.rb` | 발주번호 추출은 원본 기준 유지 |
| `translation_service.rb` | 번역 대상은 원본 유지 |

## 5. 표시 예시

### Before
```
RE: RE: FW: RFQ 6000009324 - Bosch Power Tools Set GBH 2-26 - 3rd Reminder
```

### After
```
[6000009324]  Bosch Power Tools Set GBH 2-26  [Reminder]
```

### 더 많은 예시
| 원본 제목 | display_subject | 배지 | 태그 |
|----------|----------------|------|------|
| `RE: RE: RFQ 6000009324 - Valves Set` | `Valves Set` | `6000009324` | — |
| `FW: URGENT - Price Revised for Order 12345` | `Price for Order 12345` | — | `Urgent`, `Revised` |
| `RFQ - Sika Waterproofing Materials` | `Sika Waterproofing Materials` | — | — |
| `RE: FW: RFQ 8001234 - 3rd Reminder` | — | `8001234` | `Reminder` |

## 6. 리스크 및 주의사항

| 리스크 | 대응 |
|-------|------|
| 원본 제목 손실 | `original_email_subject`는 그대로 보존, `display_subject`는 표시용 only |
| reference_no 제거 시 제목이 빈 문자열 | `subject.presence \|\| title` 폴백 |
| 태그 과다 표시 | `subject_tags` 최대 3개 제한 가능 |
| 검색 시 정제된 제목으로 못 찾음 | 검색은 원본 기준이므로 영향 없음 |

## 7. 테스트 계획

1. `bin/rails runner`로 기존 Order 데이터 대상 `display_subject` 출력 확인
2. `subject_tags` 추출 결과 확인
3. Inbox 페이지 HTTP 200 확인 + UI 비주얼 점검

---

*Plan 작성 완료. 다음 단계: `/pdca do inbox-subject-cleanup` (Design 스킵 — 단순 리팩토링)*
