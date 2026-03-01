# Design: email-signature-attachment

**Feature**: 이메일 서명 파싱 & 첨부파일 강화
**Date**: 2026-03-01
**Phase**: Design
**Ref Plan**: docs/01-plan/features/email-signature-attachment.plan.md

---

## 1. 전체 아키텍처

```
Gmail API (이메일 수신)
  ↓
EmailSyncJob (기존)
  ↓
GmailService.parse_message (기존)
  ↓
EmailToOrderService.create_order! (기존 — 수정)
  ├── EmailSignatureParserService.parse(body, html_body)  ← 신규
  │     → email_signature_json 컬럼에 저장
  └── Order.save
  ↓
EmailAttachmentExtractorService.extract_and_attach! (기존 — 수정)
  └── inline_attachment? 판별 → 인라인 이미지 skip  ← 신규 로직
  ↓
Inbox 뷰 — 발신처 카드 + 첨부파일 패널 (기존 — 수정)
```

---

## 2. DB 설계

### 2-1. Migration

```ruby
# db/migrate/YYYYMMDD_add_email_signature_to_orders.rb
class AddEmailSignatureToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :email_signature_json, :text
    # 인덱스 불필요 — JSON 텍스트 컬럼, 검색은 파싱 후 메모리에서
  end
end
```

### 2-2. email_signature_json 스키마

```json
{
  "name":    "John Smith",
  "title":   "Sales Manager",
  "company": "Sika AG",
  "phone":   "+971-2-123-4567",
  "mobile":  "+971-50-987-6543",
  "email":   "john.smith@sika.com",
  "website": "www.sika.com",
  "address": "Abu Dhabi, UAE",
  "raw":     "John Smith\nSales Manager\nSika AG\n..."
}
```

- 파싱 실패 시: `nil` (컬럼 비어있음) → 카드 미표시
- 부분 파싱 성공 시: 확인된 필드만 포함 (나머지 키 생략)

---

## 3. 서비스 설계

### 3-1. EmailSignatureParserService (신규)

**파일**: `app/services/gmail/email_signature_parser_service.rb`

```ruby
module Gmail
  class EmailSignatureParserService
    # 서명 경계 패턴 (우선순위 순)
    SIGNATURE_DELIMITERS = [
      /^--\s*$/,                          # RFC 표준: "-- "
      /^_{3,}$/,                          # ___
      /^-{3,}$/,                          # ---
      /^\*{3,}$/,                         # ***
      /^(Best\s+regards?|Regards?|Thanks?|Sincerely|Cheers|BR)[,\s]*$/i,
      /^(Kind\s+regards?|Warm\s+regards?|With\s+regards?)[,\s]*$/i,
      /^(Sent from|Get Outlook)/i,        # 모바일 클라이언트
    ].freeze

    # 필드 파싱 패턴
    PHONE_PATTERN    = /(?:T|Tel|Phone|Ph|Office|Direct|Mob|Mobile|M)[\s.:]*(\+?[\d\s\-\(\)\.]{7,20})/i
    MOBILE_PATTERN   = /(?:Mob|Mobile|Cell|M)[\s.:]*(\+?[\d\s\-\(\)\.]{7,20})/i
    EMAIL_PATTERN    = /\b([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})\b/
    URL_PATTERN      = /\b(?:www\.|https?:\/\/)([\w\-\.]+\.[a-zA-Z]{2,}(?:\/[\w\-\.\/]*)?)\b/i
    NAME_PATTERN     = /\A([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})\z/  # 영문 이름 패턴
    TITLE_KEYWORDS   = %w[Manager Director Engineer Officer Executive President VP Head Senior Lead].freeze

    def self.parse(plain_body, html_body = nil)
      new(plain_body, html_body).parse
    end

    def initialize(plain_body, html_body = nil)
      @plain = plain_body.to_s.truncate(5_000)
      @html  = html_body.to_s.truncate(10_000)
    end

    def parse
      sig_text = extract_signature_block
      return nil if sig_text.blank?

      result = {}
      lines  = sig_text.lines.map(&:strip).reject(&:blank?)

      result[:name]    = extract_name(lines)
      result[:title]   = extract_title(lines)
      result[:company] = extract_company(lines, result[:name], result[:title])
      result[:phone]   = extract_phone(sig_text)
      result[:mobile]  = extract_mobile(sig_text)
      result[:email]   = extract_email(sig_text)
      result[:website] = extract_website(sig_text)
      result[:address] = extract_address(lines)
      result[:raw]     = sig_text.truncate(500)

      result.compact.presence
    end

    private
    # ... 각 메서드 상세 구현
  end
end
```

**핵심 메서드 상세**:

```ruby
# 서명 경계 감지 — plain text 우선, HTML fallback
def extract_signature_block
  # 1. plain text에서 경계 탐지
  lines = @plain.lines
  delimiter_idx = lines.each_with_index.find do |line, i|
    SIGNATURE_DELIMITERS.any? { |pat| line.strip.match?(pat) }
  end&.last

  if delimiter_idx
    sig = lines[(delimiter_idx + 1)..].join.strip
    return sig if sig.length >= 10
  end

  # 2. 마지막 20% 텍스트를 서명으로 간주 (경계 없는 경우)
  total = lines.length
  last_n = [ (total * 0.25).ceil, 15 ].min
  lines.last(last_n).join.strip.presence
end

def extract_name(lines)
  lines.each do |line|
    next if line.match?(EMAIL_PATTERN) || line.match?(PHONE_PATTERN)
    next if line.match?(/^\+?[\d\s\-\(\)]+$/)   # 전화번호만인 줄
    return line if line.match?(NAME_PATTERN)
  end
  nil
end

def extract_title(lines)
  lines.each do |line|
    return line if TITLE_KEYWORDS.any? { |kw| line.include?(kw) } && line.length < 60
  end
  nil
end

def extract_phone(text)
  m = text.match(PHONE_PATTERN)
  m ? m[1].strip.gsub(/\s+/, " ") : nil
end

def extract_mobile(text)
  m = text.match(MOBILE_PATTERN)
  m ? m[1].strip.gsub(/\s+/, " ") : nil
end

def extract_email(text)
  # 발신자 이메일 제외한 최초 이메일 주소
  text.scan(EMAIL_PATTERN).flatten.first
end

def extract_website(text)
  m = text.match(URL_PATTERN)
  m ? m[0].gsub(/^https?:\/\//, "").split("/").first : nil
end
```

---

### 3-2. EmailAttachmentExtractorService 수정

**파일**: `app/services/gmail/email_attachment_extractor_service.rb`

**추가 로직** — `find_attachments` 메서드에 인라인 이미지 제외:

```ruby
def find_attachments(payload)
  attachments = []
  return attachments unless payload

  if payload.filename.present? &&
     payload.body&.attachment_id &&
     !inline_attachment?(payload)          # ← 신규 조건
    attachments << payload
  end

  payload.parts&.each { |part| attachments.concat(find_attachments(part)) }
  attachments
end

# 신규 메서드
def inline_attachment?(part)
  # Content-Disposition: inline 헤더 확인
  disposition = part.headers&.find { |h| h.name.casecmp("Content-Disposition").zero? }&.value.to_s
  return true if disposition.start_with?("inline")

  # 파일명 없는 이미지 = 서명 인라인 이미지
  return true if part.filename.blank? && part.mime_type.to_s.start_with?("image/")

  # Content-ID 있으면 인라인 참조 이미지
  part.headers&.any? { |h| h.name.casecmp("Content-ID").zero? } || false
end
```

---

### 3-3. EmailToOrderService 수정

**파일**: `app/services/gmail/email_to_order_service.rb`

`create_order!` 내 Order.new 블록에 추가:

```ruby
order = Order.new(
  # ... 기존 필드들 ...
  email_signature_json: parse_signature   # ← 신규
)

private

def parse_signature
  sig = Gmail::EmailSignatureParserService.parse(
    @email[:body],
    @email[:html_body]
  )
  sig&.to_json
end
```

---

### 3-4. BackfillEmailSignatureJob (신규)

**파일**: `app/jobs/backfill_email_signature_job.rb`

```ruby
class BackfillEmailSignatureJob < ApplicationJob
  queue_as :low

  def perform(batch_size: 100)
    Order.where(email_signature_json: nil)
         .where.not(original_email_body: [nil, ""])
         .find_each(batch_size: batch_size) do |order|
      sig = Gmail::EmailSignatureParserService.parse(
        order.original_email_body,
        order.original_email_html_body
      )
      order.update_column(:email_signature_json, sig.to_json) if sig.present?
    rescue => e
      Rails.logger.warn "[BackfillSignature] Order##{order.id} failed: #{e.message}"
    end
    Rails.logger.info "[BackfillSignature] Completed"
  end
end
```

---

## 4. UI 설계

### 4-1. 발신처 카드 컴포넌트 (Inbox 상세 패널)

**위치**: `app/views/inbox/index.html.erb` — RFQ 판정 배너 위, 이메일 헤더 아래

**ERB 구조**:

```erb
<%# 발신처 카드 — email_signature_json 있는 경우만 표시 %>
<% if (sig_json = order.email_signature_json.presence) %>
  <% sig = JSON.parse(sig_json) rescue {} %>
  <% if sig.present? %>
    <div class="mx-6 mt-4 p-4 bg-gray-50 dark:bg-gray-800/50
                border border-gray-200 dark:border-gray-700 rounded-lg">

      <%# 이름 + 직책 헤더 %>
      <div class="flex items-center gap-3 mb-3">
        <%# 이니셜 아바타 %>
        <div class="w-9 h-9 rounded-full bg-gradient-to-br from-blue-500 to-indigo-600
                    flex items-center justify-center flex-shrink-0">
          <span class="text-white text-sm font-bold">
            <%= sig["name"]&.first&.upcase || "?" %>
          </span>
        </div>
        <div>
          <p class="text-sm font-semibold text-gray-900 dark:text-white">
            <%= sig["name"] %>
          </p>
          <p class="text-xs text-gray-500 dark:text-gray-400">
            <%= [sig["title"], sig["company"]].compact.join(" · ") %>
          </p>
        </div>
      </div>

      <%# 연락처 정보 그리드 %>
      <div class="grid grid-cols-1 gap-1.5">
        <% if sig["phone"].present? %>
          <div class="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
            <%# Phone SVG icon %>
            <svg class="w-3.5 h-3.5 text-gray-400 flex-shrink-0" ...>...</svg>
            <span><%= sig["phone"] %></span>
          </div>
        <% end %>
        <% if sig["mobile"].present? && sig["mobile"] != sig["phone"] %>
          <div class="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
            <svg class="w-3.5 h-3.5 text-gray-400 flex-shrink-0" ...>...</svg>
            <span><%= sig["mobile"] %></span>
          </div>
        <% end %>
        <% if sig["email"].present? %>
          <a href="mailto:<%= sig["email"] %>"
             class="flex items-center gap-2 text-xs text-blue-600 dark:text-blue-400 hover:underline">
            <svg class="w-3.5 h-3.5 flex-shrink-0" ...>...</svg>
            <span><%= sig["email"] %></span>
          </a>
        <% end %>
        <% if sig["website"].present? %>
          <a href="https://<%= sig["website"] %>" target="_blank" rel="noopener"
             class="flex items-center gap-2 text-xs text-blue-600 dark:text-blue-400 hover:underline">
            <svg class="w-3.5 h-3.5 flex-shrink-0" ...>...</svg>
            <span><%= sig["website"] %></span>
          </a>
        <% end %>
        <% if sig["address"].present? %>
          <div class="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
            <svg class="w-3.5 h-3.5 text-gray-400 flex-shrink-0" ...>...</svg>
            <span><%= sig["address"] %></span>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>
<% end %>
```

### 4-2. 발신처 카드 시각 설계

```
┌─────────────────────────────────────────────────┐
│  [JS]  John Smith                               │
│        Sales Manager · Sika AG                 │
│─────────────────────────────────────────────────│
│  ☎  +971-2-123-4567                            │
│  📱  +971-50-987-6543                          │
│  ✉  john.smith@sika.com          (클릭→mailto) │
│  🌐  www.sika.com                (클릭→새탭)   │
│  📍  Abu Dhabi, UAE                            │
└─────────────────────────────────────────────────┘
```

- 배경: `bg-gray-50 dark:bg-gray-800/50`
- 보더: `border border-gray-200 dark:border-gray-700`
- 아바타: 이니셜 기반 그라디언트 원형
- 아이콘: Feather Icons 라인 스타일, `w-3.5 h-3.5`

### 4-3. 첨부파일 패널 개선사항

**인라인 이미지 제외 후**: 실제 첨부파일만 목록에 표시

**파일 타입 아이콘 매핑**:

```ruby
icon_color = case blob.content_type
  when /pdf/           then "text-red-500"
  when /sheet|excel/   then "text-green-600"
  when /word|document/ then "text-blue-600"
  when /image/         then "text-purple-500"
  when /zip|compress/  then "text-yellow-600"
  else                      "text-gray-500"
end
```

**빈 첨부파일 상태**: 인라인 이미지 제외 후 실제 첨부파일이 없으면 패널 자체를 숨김

---

## 5. Order 모델 수정

```ruby
# app/models/order.rb

# 기존 has_many_attached :attachments 유지

# 서명 정보 접근 헬퍼
def email_signature
  return nil if email_signature_json.blank?
  JSON.parse(email_signature_json)
rescue JSON::ParserError
  nil
end

def sender_name
  email_signature&.dig("name")
end

def sender_company
  email_signature&.dig("company")
end
```

---

## 6. 파일 목록 및 변경 범위

### 신규 생성 (3개)

| 파일 | 역할 |
|------|------|
| `app/services/gmail/email_signature_parser_service.rb` | 서명 블록 파싱 서비스 |
| `db/migrate/YYYYMMDD_add_email_signature_to_orders.rb` | DB 마이그레이션 |
| `app/jobs/backfill_email_signature_job.rb` | 기존 데이터 백필 |

### 수정 (4개)

| 파일 | 변경 내용 |
|------|----------|
| `app/services/gmail/email_to_order_service.rb` | `parse_signature` 메서드 추가, Order.new에 필드 추가 |
| `app/services/gmail/email_attachment_extractor_service.rb` | `inline_attachment?` 메서드 추가, `find_attachments` 조건 추가 |
| `app/models/order.rb` | `email_signature`, `sender_name`, `sender_company` 헬퍼 추가 |
| `app/views/inbox/index.html.erb` | 발신처 카드 ERB 추가, 첨부파일 패널 아이콘 개선 |

---

## 7. 구현 순서 (Do Phase 체크리스트)

```
[ ] Step 1: Migration 생성 & 실행
    - add_column :orders, :email_signature_json, :text
    - bin/rails db:migrate

[ ] Step 2: EmailSignatureParserService 구현
    - SIGNATURE_DELIMITERS 패턴 정의
    - extract_signature_block (경계 감지)
    - 각 필드별 extract_* 메서드
    - 단독 테스트: rails runner로 샘플 이메일 파싱 확인

[ ] Step 3: EmailToOrderService 연동
    - parse_signature private 메서드 추가
    - Order.new 블록에 email_signature_json 추가

[ ] Step 4: EmailAttachmentExtractorService 수정
    - inline_attachment? 메서드 추가
    - find_attachments에 조건 추가

[ ] Step 5: Order 모델 헬퍼 추가
    - email_signature, sender_name, sender_company

[ ] Step 6: Inbox 뷰 발신처 카드 UI
    - 카드 ERB 작성
    - Feather Icons SVG 인라인 삽입
    - 다크모드 클래스 적용

[ ] Step 7: BackfillEmailSignatureJob 구현 & 실행
    - rails runner "BackfillEmailSignatureJob.perform_now"
    - 처리 건수 로그 확인

[ ] Step 8: 동작 확인
    - 기존 Order 중 email_signature_json 채워진 건수 확인
    - Inbox에서 서명 카드 표시 확인
    - 첨부파일 목록에서 인라인 이미지 제외 확인
```

---

## 8. 엣지 케이스 처리

| 케이스 | 처리 방법 |
|--------|----------|
| 서명 파싱 실패 | `nil` 반환 → 카드 미표시, 에러 무시 |
| JSON 파싱 오류 | `rescue JSON::ParserError` → `nil` 반환 |
| 이름 없는 서명 | phone/email만 있어도 카드 표시 (name 없이) |
| 아랍어/한국어 서명 | 정규식 미매칭 → 파싱 실패, graceful fallback |
| 인라인 이미지만 있는 이메일 | 첨부파일 패널 자체 숨김 |
| 대용량 본문 | `truncate(5_000)` 후 파싱 적용 |
| 중복 이메일 주소 | 발신자 이메일 = `original_email_from`과 동일하면 skip |
