# Plan: email-signature-attachment

**Feature**: 이메일 서명 파싱 & 첨부파일 강화
**Date**: 2026-03-01
**Phase**: Plan
**Priority**: High

---

## 1. 배경 및 문제 정의

### 현재 상태 (As-Is)

| 항목 | 현황 | 문제 |
|------|------|------|
| 이메일 서명 | 파싱 없음 — 본문 전체를 raw 저장 | 발신자 회사명·직책·연락처를 수동으로 찾아야 함 |
| 첨부파일 | `EmailAttachmentExtractorService` 존재, 동기화 시 자동 처리 | 이미지(인라인 로고) 포함돼 혼잡, 파일 타입별 미리보기 없음 |
| 발신처 확인 | `sender_domain`만 저장 (예: `sika.com`) | 회사명·담당자명이 Order에 표시되지 않음 |
| 인라인 이미지 | `<img>` 태그 그대로 렌더링 | CID 참조 이미지가 깨져서 표시됨 |

### 핵심 Pain Point

```
RFQ 이메일 수신
  → 발신자 정보를 본문에서 수동으로 읽어야 함
  → "이 사람이 어느 회사 누구인지" 즉시 파악 불가
  → 첨부 파일(PDF 견적서, Excel 물량표)이 있어도 클릭 전까지 내용 불명
```

---

## 2. 목표 (To-Be)

### 2-1. 이메일 서명 파싱 (Email Signature Extraction)

이메일 본문 하단 서명 블록을 파싱하여 **발신처 카드(Sender Card)**로 표시

```
┌─ 발신처 ─────────────────────────────────────┐
│ 👤 John Smith — Sales Manager               │
│ 🏢 Sika AG                                  │
│ 📞 +971-2-123-4567                          │
│ 📧 john.smith@sika.com                      │
│ 🌐 www.sika.com                             │
│ 📍 Abu Dhabi, UAE                           │
└──────────────────────────────────────────────┘
```

**추출 대상 필드**:
- 이름 (Name) + 직책 (Title)
- 회사명 (Company)
- 전화번호 (Phone) — 모바일/사무실 구분
- 이메일 주소
- 웹사이트 URL
- 주소 (Address) — 국가·도시

### 2-2. 첨부파일 강화 (Attachment Enhancement)

| 강화 항목 | 내용 |
|----------|------|
| 파일 타입 아이콘 | PDF(빨강), Excel(초록), Word(파랑), 이미지(보라) |
| 인라인 이미지 분리 | `Content-Disposition: inline` 이미지는 첨부 목록에서 제외 (서명 로고 등) |
| PDF 미리보기 | PDF 파일 클릭 시 iframe 슬라이드다운 미리보기 |
| 다운로드 일괄 처리 | "모두 다운로드" 버튼 (ZIP) |
| 파일 크기 표시 | 숫자로 명확하게 (예: 245 KB) |
| 재동기화 버튼 | `attachment_urls`만 있고 ActiveStorage 없는 경우 "다시 가져오기" 버튼 |

### 2-3. 발신처 자동 매칭 (Sender → Client/Supplier Auto-Match)

```
서명에서 추출된 회사명
  → Client/Supplier 테이블에서 유사도 검색 (fuzzy match)
  → 매칭 결과를 Order의 client/supplier에 자동 연결 제안
  → 담당자(ContactPerson) 자동 생성 또는 매칭
```

---

## 3. 기능 범위 (Scope)

### In-Scope (이번 구현)

- [x] `EmailSignatureParserService` — 서명 블록 추출 + 필드 파싱
- [x] `Order` 모델에 `email_signature_json` 컬럼 추가
- [x] Inbox 상세 패널에 **발신처 카드** UI
- [x] 인라인 이미지(CID) 첨부파일 목록 제외 처리
- [x] 첨부파일 파일 타입별 아이콘 + 크기 표시 개선
- [x] 이미 저장된 Order 재파싱 (백그라운드 Job)

### Out-of-Scope (다음 단계)

- [ ] PDF 인라인 미리보기 (Phase 2)
- [ ] "모두 다운로드" ZIP 기능 (Phase 2)
- [ ] 서명 정보 → Client/Supplier 자동 매칭 (Phase 3 — Client Management 연동)
- [ ] AI 기반 서명 파싱 (LLM fallback) — 현재는 규칙 기반

---

## 4. 기술 설계 방향

### 4-1. 서명 파싱 전략

```
이메일 본문 (plain text 우선, HTML fallback)
  ↓
서명 경계 감지: "--", "___", "Regards,", "Best," 등 구분자 패턴
  ↓
서명 블록 텍스트 추출
  ↓
정규식 + 패턴 매칭으로 필드별 파싱:
  - 이름/직책: 첫 줄 패턴 (대문자, 영문 이름 패턴)
  - 전화: \+?[\d\s\-\(\)]{7,15}
  - 이메일: [\w.+]+@[\w.]+\.\w+
  - URL: https?://...
  - 회사: 이름 다음 줄 (Title + Company 순서 패턴)
  ↓
JSON으로 Order.email_signature_json에 저장
```

### 4-2. 인라인 이미지 처리

```ruby
# Gmail MIME 파트 판별 기준
def inline_attachment?(part)
  part.headers&.any? { |h| h.name == "Content-Disposition" && h.value.start_with?("inline") }
  || part.filename.blank? && part.mime_type.start_with?("image/")
end
```

인라인 이미지는 `AttachmentExtractor`에서 `skip` 처리 → 첨부 목록에 미노출

### 4-3. DB 변경

```ruby
# Migration
add_column :orders, :email_signature_json, :text
# → { name:, title:, company:, phone:, mobile:, email:, website:, address: }
```

### 4-4. 기존 데이터 처리

```ruby
# BackfillEmailSignatureJob
Order.where(original_email_from: ...).find_each do |order|
  next if order.email_signature_json.present?
  sig = EmailSignatureParserService.parse(order.original_email_body)
  order.update_column(:email_signature_json, sig.to_json) if sig.present?
end
```

---

## 5. UI/UX 설계

### 5-1. Inbox 상세 패널 레이아웃 변경

```
[ 이메일 헤더 — 발신자 + 날짜 ]
  ↓
[ RFQ 판정 배너 ] ← 기존 구현
  ↓
┌─ 발신처 카드 (신규) ──────────────────────┐
│ 아이콘 + 이름/직책                        │
│ 회사명 | 전화 | 이메일 | 웹사이트         │
└──────────────────────────────────────────┘
  ↓
[ 이메일 본문 탭 — 원문 / 번역 / 답변초안 ]
  ↓
[ 첨부파일 패널 (강화) ]
  - 실제 첨부파일만 표시 (인라인 이미지 제외)
  - 파일 타입 아이콘 + 크기
```

### 5-2. 발신처 카드 컴포넌트

```
┌────────────────────────────────────────────────┐
│ [avatar] John Smith                            │
│          Sales Manager · Sika AG               │
│                                                │
│ 📞 +971-2-123-4567   📱 +971-50-987-6543      │
│ 📧 john.smith@sika.com                         │
│ 🌐 www.sika.com                               │
│ 📍 Abu Dhabi, UAE                             │
│                                               │
│ [Client 연결] [연락처 저장]  ← Phase 3        │
└────────────────────────────────────────────────┘
```

- 아이콘: Feather Icons (라인 스타일)
- 배경: `bg-gray-50` / 보더: `border-gray-100`
- 파싱 실패 시 카드 미표시 (graceful fallback)

---

## 6. 구현 우선순위 및 단계

| 단계 | 작업 | 예상 범위 |
|------|------|----------|
| **Step 1** | DB 마이그레이션 (`email_signature_json` 컬럼) | 마이그레이션 파일 1개 |
| **Step 2** | `EmailSignatureParserService` 구현 | 서비스 1개 (규칙 기반) |
| **Step 3** | `EmailToOrderService`에 서명 파싱 연동 | 기존 서비스 수정 |
| **Step 4** | `EmailAttachmentExtractorService` — 인라인 이미지 제외 | 기존 서비스 수정 |
| **Step 5** | Inbox 뷰 — 발신처 카드 UI | ERB/CSS 추가 |
| **Step 6** | 기존 데이터 백필 Job | Job 1개 |

---

## 7. 성공 지표

| 지표 | 목표 |
|------|------|
| 서명 파싱 성공률 | 영문 이메일 기준 70%+ |
| 인라인 이미지 제외 | 첨부파일 목록에서 로고/서명 이미지 100% 제거 |
| 발신처 카드 표시 | 서명 파싱 성공 이메일에서 카드 즉시 표시 |
| 기존 데이터 백필 | 모든 기존 Order에 서명 파싱 적용 |

---

## 8. 위험 요소 및 대응

| 위험 | 영향 | 대응 |
|------|------|------|
| 서명 형식 다양성 | 파싱 실패 → 카드 미표시 | graceful fallback (카드 숨김), 로그 기록 |
| 아랍어·한국어 서명 | 정규식 미매칭 | Phase 2에 LLM fallback 추가 |
| 대용량 이메일 본문 | 파싱 속도 | `truncate(5_000)` 후 파싱 적용 |
| CID 이미지 처리 | Content-ID 참조 이미지 깨짐 | 인라인 이미지 자체를 첨부 목록에서 제외 |

---

## 9. 관련 파일 목록

### 신규 생성
- `app/services/gmail/email_signature_parser_service.rb`
- `db/migrate/YYYYMMDD_add_email_signature_to_orders.rb`
- `app/jobs/backfill_email_signature_job.rb`

### 수정 파일
- `app/services/gmail/email_to_order_service.rb` — 서명 파싱 연동
- `app/services/gmail/email_attachment_extractor_service.rb` — 인라인 이미지 제외
- `app/views/inbox/index.html.erb` — 발신처 카드 UI 추가
