# Plan: contact-person-management

**Feature**: 외부 담당자(Contact Person) 관리 강화
**Date**: 2026-03-01
**Phase**: Plan
**Priority**: High

---

## 1. 배경 및 문제 정의

### 현재 상태 (As-Is)

`ContactPerson` 모델과 기본 CRUD는 이미 존재한다.
Client/Supplier 상세 페이지의 "담당자" 탭에서 목록·추가·수정·삭제가 가능하다.

**그러나 다음이 부족하다:**

| 항목 | 현황 | 문제 |
|------|------|------|
| DB 필드 | name, title, email, phone, whatsapp, wechat, language, nationality, primary, notes | `mobile`(별도 모바일), `department`(부서), `linkedin`, `avatar_url`, `birthday`, `timezone` 없음 |
| 검색 | 없음 | 수백 명 담당자 중 이름/이메일로 찾을 수 없음 |
| 전체 목록 | 없음 | 발주처·거래처를 넘나드는 담당자 전체 뷰 없음 |
| 연락 이력 | 없음 | 이 담당자가 관여한 Order 목록 없음 |
| 이메일 연동 | 없음 | 이메일 서명에서 자동 추출된 정보로 담당자 생성 불가 |
| 발주처/거래처 뷰 | 기본 리스트만 | 담당자별 상세 카드, 연락 버튼(전화/WhatsApp/이메일) 이미 있으나 모바일 구분 없음 |
| 중복 방지 | 없음 | 같은 사람이 이메일 다르게 두 번 등록 가능 |

### 핵심 Pain Point

```
AtoZ2010 팀은 Abu Dhabi / Seoul 양쪽에서 수십 개 발주처·거래처와 거래.
각 회사마다 영업, 기술, CS 담당자가 다르다.
→ "Sika AG 담당자 중 기술 담당이 누구야?" 를 즉시 찾을 수 없음
→ RFQ 이메일 발신자가 기존 담당자인지 신규인지 모름
→ WhatsApp으로 연락할 번호를 별도 메모에서 찾아야 함
```

---

## 2. 목표 (To-Be)

### 2-1. 담당자 데이터 모델 강화

현재 `contact_persons` 테이블에 다음 필드를 추가한다:

| 필드 | 타입 | 설명 |
|------|------|------|
| `mobile` | string | 모바일 번호 (phone은 사무실 직통) |
| `department` | string | 부서 (Sales / Technical / CS / Procurement) |
| `linkedin` | string | LinkedIn URL |
| `timezone` | string | 시간대 (Asia/Dubai, Asia/Seoul 등) |
| `avatar_url` | string | 프로필 이미지 URL (선택) |
| `last_contacted_at` | datetime | 마지막 연락 일시 (이메일 수신 기준 자동 업데이트) |
| `source` | string | 등록 출처 (manual / email_signature / import) |

### 2-2. 전체 담당자 목록 페이지 (`/contacts`)

- 발주처·거래처 구분 없이 **전체 외부 담당자 통합 뷰**
- 검색: 이름·이메일·전화·회사명·부서
- 필터: 발주처만 / 거래처만 / 주요 담당자만
- 정렬: 이름 / 최근 연락일 / 회사명
- 카드 뷰: 이니셜 아바타 + 이름 + 직책 + 회사 + 연락 버튼

### 2-3. 담당자 상세 페이지 (`/contacts/:id`)

- 기본 정보 카드 (이름, 직책, 부서, 회사, 언어)
- 연락처 섹션 (사무실 전화, 모바일, 이메일, WhatsApp, WeChat, LinkedIn)
- 관련 Order 목록 (이 담당자가 발신한 이메일로 생성된 Order)
- 메모 (자유 텍스트)

### 2-4. 이메일 서명 자동 연동

이메일 수신 시:
1. `EmailSignatureParserService`가 서명 파싱
2. 발신자 이메일로 `ContactPerson` 검색
3. 매칭되면 → `last_contacted_at` 자동 업데이트
4. 미매칭 → Inbox 상세 패널에 **"담당자로 저장"** 버튼 제공

### 2-5. 인라인 담당자 추가 UX

발주처/거래처 상세 페이지에서 페이지 이동 없이:
- 담당자 카드를 클릭하면 **인라인 편집** (Turbo Frame)
- "+" 버튼 클릭 시 **슬라이드다운 폼** (현재는 새 페이지로 이동)
- 삭제 시 즉시 목록에서 제거 (페이지 리로드 없음)

---

## 3. 기능 범위 (Scope)

### In-Scope (이번 구현)

- [x] DB 마이그레이션 (신규 필드 5개)
- [x] `/contacts` 전체 담당자 목록 페이지
- [x] 담당자 카드 UI 개선 (부서 배지, 모바일 번호, 마지막 연락일)
- [x] Client/Supplier 상세 페이지 → 인라인 추가/수정 (Turbo Frame)
- [x] `ContactPersonsController` — index 액션 추가, Turbo 응답 추가
- [x] 이메일 수신 시 `last_contacted_at` 자동 업데이트
- [x] Inbox 발신처 카드에 "담당자로 저장" 버튼

### Out-of-Scope (다음 단계)

- [ ] 담당자 상세 페이지 (`/contacts/:id`) — Phase 2
- [ ] LinkedIn 프로필 자동 스크래핑 — Phase 3
- [ ] 담당자별 커뮤니케이션 이력 타임라인 — Phase 3
- [ ] vCard 내보내기 (.vcf) — Phase 2
- [ ] 명함 이미지 OCR → 담당자 자동 등록 — Phase 4 (AI)

---

## 4. 사용자 시나리오

### 시나리오 A: 신규 RFQ 수신 → 담당자 저장
```
1. Sika AG로부터 RFQ 이메일 수신
2. Inbox에서 이메일 열기
3. 발신처 카드에 "John Smith / Sales Manager / +971-50-987-6543" 표시
4. [Sika AG 담당자로 저장] 버튼 클릭
5. 모달 확인 후 ContactPerson 생성 (source: email_signature)
6. 이후 Sika AG 상세 페이지 → 담당자 탭에 John Smith 표시됨
```

### 시나리오 B: 거래처 담당자 연락
```
1. /contacts 접속 → "Sika" 검색
2. John Smith 카드 확인
3. WhatsApp 아이콘 클릭 → WhatsApp 딥링크 오픈
4. 또는 전화 아이콘 클릭 → tel: 딥링크
```

### 시나리오 C: 발주처 담당자 인라인 추가
```
1. Client 상세 페이지 접속
2. 담당자 탭 → "+" 클릭
3. 슬라이드다운 폼에서 이름/직책/이메일/전화 입력
4. [저장] → 목록에 즉시 추가 (페이지 이동 없음)
```

---

## 5. 핵심 데이터 모델 요약

```
ContactPerson
  belongs_to :contactable (polymorphic → Client or Supplier)

  # 기존
  name, title, email, phone, whatsapp, wechat
  language, nationality, primary, notes

  # 신규 추가
  mobile          -- 모바일 번호 (phone = 사무실)
  department      -- 부서 (Sales/Technical/CS/Procurement/Management)
  linkedin        -- LinkedIn 프로필 URL
  timezone        -- 시간대 (TZ database name)
  last_contacted_at -- 마지막 이메일 수신 일시 (자동 업데이트)
  source          -- manual / email_signature / import
```

---

## 6. UI 설계 방향

### 담당자 카드 (Client/Supplier 상세 페이지)

```
┌─────────────────────────────────────────────────┐
│  [JS]  John Smith                    ★ 주 담당자 │
│        Sales Manager                            │
│        [Sales] [English]                        │
│─────────────────────────────────────────────────│
│  ☎  +971-2-123-4567  (사무실)                  │
│  📱  +971-50-987-6543 (모바일)                 │
│  ✉  john.smith@sika.com                        │
│  💬  WhatsApp  🔗  LinkedIn                    │
│                                                 │
│  마지막 연락: 3일 전        [수정] [삭제]       │
└─────────────────────────────────────────────────┘
```

### 전체 담당자 목록 (`/contacts`)

```
[검색창]  [발주처 | 거래처 | 전체]  [이름순 | 최근연락순]

┌────────────┐ ┌────────────┐ ┌────────────┐
│ [JS]       │ │ [MK]       │ │ [AH]       │
│ John Smith │ │ Min-jun Kim│ │ Ahmed Hassan│
│ Sika AG    │ │ POSCO      │ │ Gulf Steel │
│ Sales Mgr  │ │ 기술 담당  │ │ Procurement│
│ ✉ 📱 💬   │ │ ✉ 📱 💬   │ │ ✉ 📱      │
│ D-3일      │ │ D-14일     │ │ 오늘       │
└────────────┘ └────────────┘ └────────────┘
```

---

## 7. 성공 지표

| 지표 | 목표 |
|------|------|
| 전체 담당자 검색 | `/contacts`에서 이름/이메일로 즉시 검색 |
| 인라인 추가 | 페이지 이동 없이 담당자 추가 완료 |
| 이메일 연동 | RFQ 수신 후 클릭 1번으로 담당자 저장 |
| 모바일 번호 | 사무실 전화와 모바일 분리 표시 |

---

## 8. 관련 파일 목록

### 신규 생성
- `app/views/contact_persons/index.html.erb` — 전체 담당자 목록
- `db/migrate/YYYYMMDD_add_fields_to_contact_persons.rb`

### 수정
- `app/controllers/contact_persons_controller.rb` — index 추가, Turbo 응답
- `app/models/contact_person.rb` — 신규 필드 검증, scope 추가
- `app/views/clients/show.html.erb` — Turbo Frame 인라인 편집
- `app/views/suppliers/show.html.erb` — 동일
- `app/views/inbox/index.html.erb` — "담당자로 저장" 버튼
- `config/routes.rb` — contacts 리소스 추가
- `app/services/gmail/email_to_order_service.rb` — last_contacted_at 업데이트
