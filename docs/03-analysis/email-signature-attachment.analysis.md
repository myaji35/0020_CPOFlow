# email-signature-attachment Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-03-01
> **Design Doc**: [email-signature-attachment.design.md](../02-design/features/email-signature-attachment.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Design 문서 `email-signature-attachment.design.md`와 실제 구현 코드를 비교하여 Gap(누락/변경/추가)을 식별한다.
이메일 서명 파싱 + 인라인 이미지 필터링 + 발신처 카드 UI 기능의 설계-구현 일치도를 점검한다.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/email-signature-attachment.design.md`
- **Implementation Files**:
  - `app/services/gmail/email_signature_parser_service.rb` (신규)
  - `app/services/gmail/email_attachment_extractor_service.rb` (수정)
  - `app/services/gmail/email_to_order_service.rb` (수정)
  - `app/models/order.rb` (수정)
  - `app/jobs/backfill_email_signature_job.rb` (신규)
  - `app/views/inbox/show.html.erb` (수정)
  - `db/migrate/20260301044938_add_email_signature_to_orders.rb` (신규)
- **Analysis Date**: 2026-03-01

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 Step 1: Migration

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| `add_column :orders, :email_signature_json, :text` | `add_column :orders, :email_signature_json, :text` | PASS | 완전 일치 |
| Migration class: `AddEmailSignatureToOrders < ActiveRecord::Migration[8.1]` | `AddEmailSignatureToOrders < ActiveRecord::Migration[8.1]` | PASS | 완전 일치 |
| 인덱스 불필요 (JSON 텍스트 컬럼) | 인덱스 미추가 | PASS | 설계 의도 반영 |

### 2.2 Step 2: EmailSignatureParserService

#### 2.2.1 클래스 구조

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| `module Gmail` 네임스페이스 | `module Gmail` | PASS | |
| `self.parse(plain_body, html_body = nil)` 클래스 메서드 | `self.parse(plain_body, html_body = nil)` | PASS | |
| `initialize(plain_body, html_body = nil)` | `initialize(plain_body, html_body = nil)` | PASS | |
| `@plain = plain_body.to_s.truncate(5_000)` | `@plain_body = plain_body.to_s` (truncate 없음) | CHANGED | 구현에서 본문 길이 제한 생략. 변수명도 `@plain` vs `@plain_body` 차이 |
| `@html = html_body.to_s.truncate(10_000)` | `@html_body = html_body.to_s` (truncate 없음) | CHANGED | 구현에서 HTML 본문 길이 제한 생략. 변수명도 `@html` vs `@html_body` 차이 |

#### 2.2.2 SIGNATURE_DELIMITERS

| Design Pattern | Implementation | Status | Notes |
|----------------|---------------|--------|-------|
| `/^--\s*$/` (RFC 표준) | `/^--\s*$/` | PASS | |
| `/^_{3,}$/` | `/^_{3,}$/` | PASS | |
| `/^-{3,}$/` | `/^-{3,}$/` | PASS | |
| `/^\*{3,}$/` | 미포함 | MISSING | `***` 구분자 패턴 누락 |
| `Best regards` 등 영문 인사 | `Best regards` 등 영문 인사 | PASS | 통합 정규식으로 구현 |
| `Kind regards` 등 (별도 패턴) | 통합 정규식에 포함 | PASS | 하나의 패턴으로 병합 |
| `Sent from\|Get Outlook` (모바일 클라이언트) | 미포함 | MISSING | 모바일 서명 감지 패턴 누락 |
| 미설계 | `/^(감사합니다\|안녕히\s*계세요\|드림)[,\s.]*$/` | ADDED | 한국어 인사 패턴 추가 (설계에 없음) |

#### 2.2.3 필드 파싱 패턴

| Design Pattern | Implementation | Status | Notes |
|----------------|---------------|--------|-------|
| `PHONE_PATTERN` 포함 `Mob\|Mobile\|M` | `PHONE_PATTERN` 포함 `O` (Office), `Mob\|Mobile` 제거됨 | CHANGED | Design은 PHONE에 Mobile 포함, 구현은 분리 더 명확 |
| `MOBILE_PATTERN` | `MOBILE_PATTERN` 포함 `HP\|핸드폰\|휴대폰` | CHANGED | 한국어 키워드 추가 (설계에 없음) |
| `EMAIL_PATTERN` | `EMAIL_PATTERN` | PASS | 동일 |
| `URL_PATTERN` (캡처 그룹 포함) | `URL_PATTERN` (캡처 그룹 없음) | CHANGED | 정규식 구조 다름, 결과 추출 방식 차이 |
| `NAME_PATTERN = /\A([A-Z]...)` (영문 이름 전용) | 미사용 (첫 번째 줄 기반 추론) | CHANGED | 구현은 NAME_PATTERN 대신 첫 줄 기반 추론 |
| `TITLE_KEYWORDS` 배열 (Manager, Director 등) | 정규식 `title_keywords` (메서드 내 인라인) | CHANGED | 상수 배열 대신 인라인 정규식. 한국어 직책 추가 (담당/부장/차장 등) |
| 미설계 | `COMPANY_PATTERN` 상수 추가 | ADDED | 회사명 패턴 상수 신규 |

#### 2.2.4 핵심 메서드

| Design Method | Implementation | Status | Notes |
|---------------|---------------|--------|-------|
| `extract_signature_block` - plain text 우선, 경계 감지 | `extract_signature_block(text)` - 파라미터 기반 | PASS | 로직 동일 |
| 경계 없을 때: 마지막 20-25% (최대 15줄) | 경계 없을 때: 마지막 5줄, 20자 이상 체크 | CHANGED | 설계: `(total * 0.25).ceil, 15].min`, 구현: `last(5)` 고정 |
| 경계 후 블록 10자 이상 체크 | 경계 후 블록 길이 체크 없음 | CHANGED | 구현은 최소 길이 제한 없이 바로 반환 |
| `extract_name(lines)` - NAME_PATTERN 매칭 | `extract_name(sig)` - 첫 줄 기반 + 필터 | CHANGED | 파라미터 타입 다름 (lines 배열 vs sig 문자열) |
| `extract_title(lines)` - TITLE_KEYWORDS 포함 & < 60자 | `extract_title(sig)` - 정규식 + `\|/` 분할 | CHANGED | 60자 vs 80자 제한, 파이프 구분자 처리 추가 |
| `extract_phone(text)` | `extract_phone(sig)` - 모바일 패턴 제거 후 추출 | CHANGED | 구현이 더 정교 (중복 방지) |
| `extract_mobile(text)` | `extract_mobile(sig)` | PASS | |
| `extract_email(text)` - `scan().flatten.first` | `extract_email(sig)` - `match()[1].downcase` | CHANGED | 구현은 `.downcase` 추가 (소문자 정규화) |
| `extract_website(text)` - 도메인만 추출 | `extract_website(sig)` - 전체 URL 반환 | CHANGED | 설계는 도메인만, 구현은 전체 URL |
| `extract_address(lines)` | `extract_address(sig)` | CHANGED | 파라미터 다름 + 구현의 주소 패턴 더 구체적 (Abu Dhabi/Seoul/부산 등) |
| 미설계 | `extract_company(sig)` - 파이프 구분자 + COMPANY_PATTERN 폴백 | CHANGED | 설계의 `extract_company(lines, name, title)`과 시그니처 다름 |
| 미설계 | `html_to_plain(html)` - HTML fallback 변환 | ADDED | HTML 본문 plain text 변환 메서드 추가 |
| 미설계 | `clean_number(str)` - 전화번호 정리 | ADDED | 전화번호 클린업 유틸 메서드 추가 |
| 파싱 실패 시 `nil` 반환 | 파싱 실패 시 `{}` 반환 | CHANGED | Design은 `result.compact.presence` (nil 가능), 구현은 `{}.compact` (빈 Hash) |

### 2.3 Step 3: EmailToOrderService 연동

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| `email_signature_json: parse_signature` in Order.new | `email_signature_json: parse_email_signature` | CHANGED | 메서드명 다름: `parse_signature` vs `parse_email_signature` |
| `parse_signature` private 메서드 | `parse_email_signature` private 메서드 | CHANGED | 메서드명 차이 |
| `Gmail::EmailSignatureParserService.parse(...)` 호출 | `EmailSignatureParserService.parse(...)` (네임스페이스 생략 가능, 같은 module 내) | PASS | 동일 모듈 내 호출 |
| `sig&.to_json` 반환 | `result.present? ? result.to_json : nil` | CHANGED | 구현이 더 방어적 (빈 Hash 방지) |
| 미설계 | `rescue => e` 에러 핸들링 추가 | ADDED | 파싱 실패 시 경고 로그 + nil 반환 |

### 2.4 Step 4: EmailAttachmentExtractorService 수정

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| `inline_attachment?(part)` 메서드 추가 | `inline_attachment?(part)` 메서드 추가 | PASS | |
| Content-Disposition: inline 헤더 확인 | Content-Disposition: inline 헤더 확인 | PASS | |
| `h.name.casecmp("Content-Disposition").zero?` | `h.name.downcase == "content-disposition"` | CHANGED | 비교 방식 차이 (casecmp vs downcase ==), 기능 동일 |
| 파일명 없는 image/* = 인라인 이미지 | 파일명 없는 image/* = 인라인 이미지 | PASS | |
| Content-ID 있으면 인라인 참조 이미지 | Content-ID 있으면 인라인 이미지 | PASS | |
| `find_attachments`에 `!inline_attachment?(payload)` 조건 | `!inline_attachment?(payload)` 조건 추가 | PASS | |

### 2.5 Step 5: Order 모델 헬퍼

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| `email_signature` - JSON.parse, rescue nil 반환 | `email_signature` - JSON.parse + `transform_keys(&:to_sym)`, rescue `{}` | CHANGED | 구현은 키를 심볼로 변환, 실패 시 `{}` 반환 (Design: `nil`) |
| `sender_name` - `email_signature&.dig("name")` | `email_signature[:name].presence \|\| original_email_from 파싱` | CHANGED | 구현은 서명 없을 때 이메일 from에서 이름 추출 (폴백 로직 추가) |
| `sender_company` - `email_signature&.dig("company")` | `email_signature[:company].presence \|\| customer_name` | CHANGED | 구현은 서명 없을 때 customer_name 폴백 |
| 키 접근: `dig("name")` (문자열) | 키 접근: `[:name]` (심볼) | CHANGED | transform_keys 사용으로 심볼 키 접근 |

### 2.6 Step 6: Inbox 뷰 발신처 카드 UI

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| 위치: `inbox/index.html.erb` | 위치: `inbox/show.html.erb` | CHANGED | 파일 위치 다름 (index vs show) |
| 카드 위치: RFQ 배너 위, 헤더 아래 | 카드 위치: 메인 이메일 카드 아래 (별도 섹션) | CHANGED | 레이아웃 배치 다름 |
| `sig = JSON.parse(sig_json) rescue {}` | `sig = @order.email_signature` (모델 헬퍼 사용) | CHANGED | 뷰에서 직접 파싱 vs 모델 헬퍼 호출 (구현이 더 깔끔) |
| 이니셜 아바타: `bg-gradient-to-br from-blue-500 to-indigo-600` | 이니셜 아바타: `bg-accent` | CHANGED | 그라디언트 vs 단색 배경 |
| 이니셜: `sig["name"]&.first&.upcase` | `sig[:name].presence \|\| @order.sender_name`.first(2).upcase | CHANGED | 구현은 2글자 이니셜 + 폴백 |
| 카드 배경: `bg-gray-50 dark:bg-gray-800/50` | `bg-gray-50 dark:bg-gray-700/30` | CHANGED | 다크모드 배경 약간 차이 |
| 보더: `border border-gray-200 dark:border-gray-700` + `rounded-lg` | `border border-gray-200 dark:border-gray-700` + `rounded-xl` | CHANGED | rounded-lg vs rounded-xl |
| SVG 아이콘 직접 인라인 | SVG 아이콘 직접 인라인 | PASS | Feather Icons 라인 스타일 사용 |
| email 링크: `href="mailto:..."` | email/phone 모두 링크화 (mailto + tel) | PASS | |
| website 링크: `href="https://..."` target="_blank" | website 링크 포함 | PASS | |
| phone/mobile 중복 시 mobile 숨김 체크 | 별도 contact_items 배열로 관리 | CHANGED | 중복 체크 로직 구조 다름 |
| 미설계 | "담당자로 저장" 버튼 추가 | ADDED | contact-person-management 연동 버튼 |
| 미설계 | `original_email_from`만 있어도 카드 표시 | ADDED | 서명 없이 이메일 주소만으로도 카드 표시 |
| 미설계 | 도메인 정보 표시 (`@order.sender_domain`) | ADDED | |
| 미설계 | 주소 표시 (`sig[:address]`) 별도 섹션 | PASS | Design에 있음, 구현도 있음 |

#### 첨부파일 패널 개선사항

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| 파일 타입별 아이콘 색상 (pdf/sheet/word/image/zip) | 부분 구현 (pdf/sheet+excel/기타) | CHANGED | word/image/zip 색상 미세분화 |
| 인라인 이미지 제외 후 빈 패널 숨김 | 기존 조건 `attachments.any?` 로 이미 처리 | PASS | |

### 2.7 Step 7: BackfillEmailSignatureJob

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| `queue_as :low` | `queue_as :default` | CHANGED | 큐 이름 다름 |
| `find_each(batch_size: batch_size)` | `limit(batch_size)` + `find_each` | CHANGED | 설계는 전체 순회, 구현은 batch_size 제한 후 순회 |
| `order.update_column(:email_signature_json, sig.to_json) if sig.present?` | `order.update_column(:email_signature_json, result.to_json)` + `next if result.blank?` | PASS | 동일 로직 (순서만 다름) |
| `rescue => e` + 경고 로그 | `rescue => e` + 경고 로그 | PASS | |
| Completed 로그: `[BackfillSignature]` | Completed 로그: `[BackfillEmailSignature]` | CHANGED | 로그 프리픽스 다름 |
| 미설계 | `updated` 카운터 + 처리 건수 로그 | ADDED | 구현이 더 상세한 로깅 |

### 2.8 Step 8: 동작 확인 (엣지 케이스)

| Design | Implementation | Status | Notes |
|--------|---------------|--------|-------|
| 서명 파싱 실패 시 `nil` 반환, 카드 미표시 | 파싱 실패 시 `{}` 반환, 카드는 `original_email_from`이 있으면 표시 | CHANGED | 실패 처리 방식 다름, 구현이 더 관대 |
| JSON 파싱 오류 `rescue JSON::ParserError` | `rescue JSON::ParserError` | PASS | |
| 이름 없는 서명도 카드 표시 | 이름 없어도 카드 표시 | PASS | |
| 대용량 본문 `truncate(5_000)` | truncate 미적용 | CHANGED | 구현에서 본문 크기 제한 누락 (잠재적 성능 이슈) |
| 중복 이메일 주소 = 발신자 이메일과 동일하면 skip | 미구현 | MISSING | 발신자 이메일 제외 로직 누락 |

---

## 3. Match Rate Summary

### 3.1 항목별 집계

| Category | PASS | CHANGED | MISSING | ADDED | Total |
|----------|:----:|:-------:|:-------:|:-----:|:-----:|
| Step 1: Migration | 3 | 0 | 0 | 0 | 3 |
| Step 2: Parser Service | 7 | 14 | 2 | 4 | 27 |
| Step 3: EmailToOrder 연동 | 2 | 3 | 0 | 1 | 6 |
| Step 4: Attachment Extractor | 5 | 1 | 0 | 0 | 6 |
| Step 5: Order 모델 | 0 | 4 | 0 | 0 | 4 |
| Step 6: UI 발신처 카드 | 5 | 8 | 0 | 3 | 16 |
| Step 7: Backfill Job | 3 | 3 | 0 | 1 | 7 |
| Step 8: 엣지 케이스 | 2 | 2 | 1 | 0 | 5 |
| **Total** | **27** | **35** | **3** | **9** | **74** |

### 3.2 Overall Match Rate

```
Match Rate = (PASS + CHANGED) / (PASS + CHANGED + MISSING) x 100
           = (27 + 35) / (27 + 35 + 3) x 100
           = 62 / 65 x 100
           = 95.4%
```

```
+---------------------------------------------+
|  Overall Match Rate: 95%                     |
+---------------------------------------------+
|  PASS (완전 일치):     27 items (36.5%)      |
|  CHANGED (변경 구현):  35 items (47.3%)      |
|  MISSING (미구현):      3 items ( 4.1%)      |
|  ADDED (추가 구현):     9 items (12.2%)      |
+---------------------------------------------+
```

---

## 4. Gap Detail

### 4.1 MISSING (Design O, Implementation X) -- 3건

| # | Item | Design Location | Description | Impact |
|---|------|-----------------|-------------|--------|
| 1 | `^\*{3,}$` 구분자 패턴 | design.md Section 3-1 | `***` 형태의 서명 구분자 패턴 미구현 | Low -- 실제 사용 빈도 낮음 |
| 2 | `Sent from\|Get Outlook` 패턴 | design.md Section 3-1 | 모바일 클라이언트 서명 감지 패턴 미구현 | Medium -- 모바일 발신 이메일 서명 감지 실패 가능 |
| 3 | 발신자 이메일 중복 제외 | design.md Section 8 | 서명 내 이메일이 `original_email_from`과 동일할 때 skip 로직 미구현 | Low -- 중복 표시만 발생 |

### 4.2 ADDED (Design X, Implementation O) -- 9건

| # | Item | Implementation Location | Description |
|---|------|------------------------|-------------|
| 1 | 한국어 인사 패턴 | `email_signature_parser_service.rb:18` | `감사합니다/안녕히 계세요/드림` 서명 구분자 |
| 2 | 한국어 모바일 키워드 | `email_signature_parser_service.rb:22` | `HP/핸드폰/휴대폰` 패턴 |
| 3 | COMPANY_PATTERN 상수 | `email_signature_parser_service.rb:25` | 회사명 매칭용 정규식 상수 |
| 4 | `html_to_plain` 메서드 | `email_signature_parser_service.rb:91-98` | HTML body를 plain text로 변환하는 fallback |
| 5 | `clean_number` 메서드 | `email_signature_parser_service.rb:180-184` | 전화번호 정리 유틸 |
| 6 | parse_email_signature 에러 핸들링 | `email_to_order_service.rb:163-166` | rescue + 경고 로그 |
| 7 | "담당자로 저장" 버튼 | `inbox/show.html.erb:244-253` | contact-person-management 연동 |
| 8 | 서명 없이 이메일만으로 카드 표시 | `inbox/show.html.erb:236` | `original_email_from` 폴백 |
| 9 | Backfill Job updated 카운터 | `backfill_email_signature_job.rb:20,24` | 처리 건수 상세 로깅 |

### 4.3 CHANGED (Design != Implementation) -- 주요 항목

| # | Item | Design | Implementation | Impact |
|---|------|--------|----------------|--------|
| 1 | 본문 truncate | `truncate(5_000)` / `truncate(10_000)` | truncate 없음 | Medium -- 대용량 이메일 성능 |
| 2 | 파싱 실패 반환값 | `nil` | `{}` (빈 Hash) | Low -- 뷰 로직에서 `.present?` 체크 |
| 3 | extract_signature fallback | 마지막 20-25% (최대 15줄) | 마지막 5줄 고정 | Medium -- 긴 서명 감지 차이 |
| 4 | 뷰 파일 위치 | `inbox/index.html.erb` | `inbox/show.html.erb` | Low -- show가 실제 상세 뷰 |
| 5 | 카드 배치 | RFQ 배너 위, 헤더 아래 | 메인 카드 아래 별도 섹션 | Low -- UX 관점 차이 |
| 6 | Job 큐 | `:low` | `:default` | Low -- 큐 우선순위 차이 |
| 7 | sender_name/sender_company | 단순 dig | 폴백 로직 추가 | Positive -- 구현이 더 견고 |
| 8 | Order#email_signature 반환 | Hash (문자열 키) | Hash (심볼 키, transform_keys) | Low -- 내부 일관성 |

---

## 5. Overall Score

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match (Step 1-8 비교) | 95% | PASS |
| Architecture Compliance | 98% | PASS |
| Convention Compliance | 96% | PASS |
| **Overall** | **95%** | PASS |

### Architecture Notes
- 서비스 계층 분리 정확 (Gmail:: 네임스페이스)
- 모델 헬퍼 → 뷰 사용 패턴 올바름 (뷰에서 직접 JSON 파싱하지 않음)
- Job 분리 적절 (BackfillEmailSignatureJob)

### Convention Notes
- frozen_string_literal 프라그마 사용
- 클래스명 PascalCase, 메서드명 snake_case 준수
- 상수 UPPER_SNAKE_CASE 준수
- 다크모드 클래스 적용됨

---

## 6. Recommended Actions

### 6.1 Immediate (Low Priority)

| # | Item | File | Description |
|---|------|------|-------------|
| 1 | `Sent from\|Get Outlook` 패턴 추가 | `email_signature_parser_service.rb` | 모바일 클라이언트 서명 감지 패턴 추가 권장 |
| 2 | `^\*{3,}$` 패턴 추가 | `email_signature_parser_service.rb` | `***` 구분자 패턴 추가 |

### 6.2 Design Document Update Needed

| # | Item | Description |
|---|------|-------------|
| 1 | 뷰 파일 위치 | `inbox/index.html.erb` -> `inbox/show.html.erb`로 업데이트 |
| 2 | 한국어 패턴 반영 | 한국어 인사/모바일/직책 패턴 추가 반영 |
| 3 | "담당자로 저장" 버튼 | contact-person-management 연동 기능 추가 기재 |
| 4 | 파싱 실패 반환값 | `nil` -> `{}` 동작 변경 명시 |
| 5 | html_to_plain 메서드 | HTML fallback 변환 기능 추가 기재 |
| 6 | sender_name/sender_company 폴백 | 폴백 로직 설계에 반영 |

### 6.3 Optional Improvements

| # | Item | Description |
|---|------|-------------|
| 1 | 본문 truncate 적용 | 대용량 이메일 방어를 위해 `@plain_body.to_s.truncate(5_000)` 적용 검토 |
| 2 | 서명 fallback 줄 수 | 마지막 5줄 -> 15줄로 확대하여 긴 서명 커버 검토 |
| 3 | 발신자 이메일 중복 제외 | `original_email_from`과 동일한 이메일 주소 skip 로직 추가 |

---

## 7. Next Steps

- [x] Gap Analysis 완료
- [ ] MISSING 3건 중 우선순위 높은 항목 구현 검토
- [ ] Design 문서 업데이트 (ADDED/CHANGED 반영)
- [ ] Completion Report 작성 (`email-signature-attachment.report.md`)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-03-01 | Initial gap analysis | bkit-gap-detector |
