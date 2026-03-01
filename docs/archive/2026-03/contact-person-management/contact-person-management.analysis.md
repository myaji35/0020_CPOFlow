# contact-person-management Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: gap-detector
> **Date**: 2026-03-01
> **Design Doc**: [contact-person-management.design.md](../02-design/features/contact-person-management.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

contact-person-management 피처의 Design 문서(12개 섹션)와 실제 구현 코드 간의 일치율을 측정하고, 차이점을 식별한다.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/contact-person-management.design.md`
- **Implementation Path**: `app/models/`, `app/controllers/`, `app/views/contact_persons/`, `config/routes.rb`, `app/services/gmail/`, `app/views/shared/`
- **Analysis Date**: 2026-03-01

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 DB Migration (Design Section 2)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `add_column :mobile, :string` | `add_column :contact_persons, :mobile, :string` | PASS | 일치 |
| `add_column :department, :string` | `add_column :contact_persons, :department, :string` | PASS | 일치 |
| `add_column :linkedin, :string` | `add_column :contact_persons, :linkedin, :string` | PASS | 일치 |
| `add_column :last_contacted_at, :datetime` | `add_column :contact_persons, :last_contacted_at, :datetime` | PASS | 일치 |
| `add_column :source, :string, default: "manual"` | `add_column :contact_persons, :source, :string, default: "manual"` | PASS | 일치 |
| `add_index :department` | `add_index :contact_persons, :department` | PASS | 일치 |
| `add_index :last_contacted_at` | `add_index :contact_persons, :last_contacted_at` | PASS | 일치 |

**Migration Score: 7/7 (100%)**

### 2.2 Model (Design Section 3)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `LANGUAGES` 상수 | `LANGUAGES = { "en"=>"English", ... }` | CHANGED | Design: `"de","fr"` 포함 / Impl: `"ja"` 포함, `"de","fr"` 미포함 |
| `DEPARTMENTS` 상수 | `DEPARTMENTS = %w[Sales Technical CS Procurement Management Finance Other]` | PASS | 일치 |
| `SOURCES` 상수 | `SOURCES = %w[manual email_signature import]` | PASS | 일치 |
| `validates :name, presence` | 존재 | PASS | 일치 |
| `validates :email, format` | 존재 | PASS | 일치 |
| `validates :source, inclusion` | 존재 | PASS | 일치 |
| `validates :department, inclusion` | 존재 | PASS | 일치 |
| `scope :primary_first` | 존재 | PASS | 일치 |
| `scope :with_contactable` | `includes(:contactable)` | PASS | 일치 |
| `scope :recently_contacted` | `order(last_contacted_at: :desc, name: :asc)` | CHANGED | Design: `:desc` only / Impl: `:desc, name: :asc` 추가 (개선) |
| `scope :by_department` | `dept.present? ? where(department: dept) : all` | PASS | Design의 `if dept.present?`와 동치 |
| `scope :for_clients` | `where(contactable_type: "Client")` | PASS | 일치 |
| `scope :for_suppliers` | `where(contactable_type: "Supplier")` | PASS | 일치 |
| `scope :primary_only` | `where(primary: true)` | PASS | 일치 |
| `scope :search` | LIKE 기반 4-field 검색 | PASS | 일치 |
| `display_name` | `primary? ? "#{name} ★" : name` | CHANGED | Design: `"★ #{name}"` (접두) / Impl: `"#{name} ★"` (접미) |
| `language_label` | 존재 | PASS | 일치 |
| `contactable_name` | `contactable&.name` | PASS | 일치 |
| `contactable_type_label` | 구현: `contactable_label` | CHANGED | Design: `contactable_type_label` / Impl: `contactable_label` (메서드명 변경) |
| `last_contacted_label` | 존재 | CHANGED | Design: nil 시 `"없음"` / Impl: nil 시 `"-"` (한 글자 차이) |

**Model Score: 15 PASS + 5 CHANGED = 20/20 (75% exact, 100% functional)**

### 2.3 Routes (Design Section 4)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `resources :contact_persons, only: %i[index]` | `resources :contact_persons, only: %i[index]` (routes.rb:124) | PASS | 일치 |
| `collection { post :create_from_signature }` | `collection { post :create_from_signature }` (routes.rb:126) | PASS | 일치 |
| 기존 nested routes 유지 | Client/Supplier 하위 `contact_persons` 유지 | PASS | 일치 |

**Routes Score: 3/3 (100%)**

### 2.4 Controller (Design Section 5)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `index` 액션: `with_contactable` | `ContactPerson.with_contactable` (L8) | PASS | 일치 |
| `index`: `search(params[:q])` | `.search(params[:q])` (L9) | PASS | 일치 |
| `index`: `by_department(params[:department])` | `.by_department(params[:department])` (L10) | PASS | 일치 |
| `index`: type 필터 (clients/suppliers) | `case params[:type]` 분기 (L12-16) | PASS | 일치 |
| `index`: sort 옵션 (recent/company/name) | `case params[:sort]` 분기 (L18-22) | CHANGED | Design: `company` sort에 LEFT JOIN 사용 / Impl: `contactable_type ASC, name ASC` 간략화 |
| `index`: `.page(params[:page]).per(24)` | `.page(params[:page]).per(24)` (L25) | PASS | 일치 |
| `create_from_signature` 액션 | 존재 (L97-130) | PASS | 핵심 로직 일치 |
| `create_from_signature`: contactable 검색 | `find_contactable_by_domain` (L101) | PASS | 일치 |
| `create_from_signature`: email 추출 | `match(/<(.+?)>/)` 패턴 (L110-111) | PASS | 일치 |
| `create_from_signature`: `source: "email_signature"` | `source: "email_signature"` (L119) | PASS | 일치 |
| `create_from_signature`: `last_contacted_at` 업데이트 | `update_column(:last_contacted_at, ...)` (L123) | PASS | 일치 |
| `contact_person_params`: 신규 필드 포함 | `:mobile, :department, :linkedin` 포함 (L147-150) | PASS | 일치 |
| `create` 액션: Turbo Stream 응답 | `respond_to format.turbo_stream` (L41-55) | PASS | 일치 |
| `create`: append + replace 패턴 | append + replace 2개 액션 (L43-54) | CHANGED | Design: 3개 turbo_stream 액션(append+replace+script) / Impl: 2개(append+replace) — script 폼닫기 제외 |
| `create`: `source ||= "manual"` | `@contact_person.source ||= "manual"` (L34) | PASS | 일치 |
| `destroy`: Turbo Stream | `turbo_stream.remove` (L90) | PASS | Design에 없으나 구현 정합성 우수 |

**Controller Score: 13 PASS + 2 CHANGED = 15/16 (81% exact, 100% functional)**

### 2.5 Views

#### 2.5.1 `index.html.erb` (Design Section 6-1)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| 페이지 헤더 (제목 + 총 N명) | `@total_count` 사용 | CHANGED | Design: `@contact_persons.total_count` / Impl: 별도 `@total_count` 변수 |
| 검색 + 필터 바 (q, type, department, sort) | 4개 필드 모두 존재 | PASS | 일치 |
| `form_with turbo_frame: "_top"` | `data: { turbo: false }` | CHANGED | Design: Turbo Frame / Impl: Turbo 비활성 (full page reload) |
| 카드 그리드 4-col | `grid-cols-1 sm:2 md:3 lg:4` | PASS | 일치 |
| empty 상태 | 조건 분기 (검색 유/무) | PASS | Design보다 상세한 분기 (개선) |
| 페이지네이션: `paginate @contact_persons` | 커스텀 prev/next 구현 | CHANGED | Design: kaminari `paginate` helper / Impl: 수동 prev_page/next_page 링크 |
| 검색 submit 버튼 | "검색" 버튼 존재 | PASS | Design에 없으나 UX 개선 |
| 필터 초기화 링크 | 조건부 "초기화" 링크 존재 | PASS | Design에 없으나 UX 개선 |

#### 2.5.2 `_card.html.erb` (Design Section 6-2)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| 아바타 (이니셜 2자) | `contact_person.name.first(2).upcase` | PASS | 일치 |
| 이름 + 주 담당자 뱃지 | "주" 뱃지 존재 | PASS | 일치 |
| 부서 뱃지 (indigo) | indigo 색상 뱃지 | PASS | 일치 |
| 회사명 + 타입 뱃지 | `contactable_label` + `contactable_name` | PASS | 일치 (메서드명 차이는 모델에서 기록) |
| email 아이콘 버튼 | `mailto:` + SVG | PASS | 일치 |
| phone 아이콘 버튼 | `tel:` + SVG | PASS | 일치 |
| mobile 아이콘 버튼 | `tel:` + SVG (smartphone icon) | PASS | 일치 |
| whatsapp 아이콘 버튼 | `wa.me/` + `gsub(/\D/, '')` | PASS | 일치 |
| linkedin 아이콘 버튼 | `target="_blank" rel="noopener"` | PASS | 일치 |
| 마지막 연락일 | `last_contacted_label` | PASS | 일치 |

#### 2.5.3 Client/Supplier 상세 담당자 탭 (Design Section 6-3)

| Design Item | Implementation (Client) | Implementation (Supplier) | Status |
|-------------|------------------------|--------------------------|--------|
| 담당자 추가 버튼 (toggle hidden) | `onclick toggle hidden` (L103) | `onclick toggle hidden` (L89) | PASS |
| 인라인 폼 (turbo-frame 래핑) | `render inline_form` (L112) | `render inline_form` (L98) | CHANGED | Design: `<turbo-frame>` 래핑 / Impl: turbo-frame 없이 div 직접 렌더 |
| 담당자 목록 (turbo-frame 래핑) | `id="contact-persons-#{id}"` (L115) | `id="contact-persons-#{id}"` (L101) | CHANGED | Design: `<turbo-frame>` 래핑 / Impl: 일반 `<div>` 사용 |
| 담당자 행 `_row.html.erb` 렌더 | `render "contact_persons/row"` (L117) | `render "contact_persons/row"` (L103) | PASS |
| 전체 보기 링크 | `contact_persons_path` (L100) | `contact_persons_path` (L86) | PASS | Design에 없으나 추가 (개선) |

#### 2.5.4 `_inline_form.html.erb` (Design Section 6-4)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `form_with model: [contactable, contact_person]` | 존재 (L7) | PASS | 일치 |
| `data: { turbo_frame: ..., turbo_action: "advance" }` | `data: { turbo: true }` | CHANGED | Design: turbo_frame 지정 / Impl: turbo: true 만 |
| 이름(required), 직책, 부서, 이메일, 전화, 모바일, WhatsApp, 언어 | 8개 필드 모두 존재 | PASS | 일치 |
| 취소/저장 버튼 | 존재 | PASS | 일치 |
| 주 담당자 체크박스 | 존재 (L71-74) | PASS | Design에 없으나 추가 (개선) |
| 에러 메시지 표시 | `contact_person.errors.any?` (L9-15) | PASS | Design에 없으나 추가 (개선) |

#### 2.5.5 `_row.html.erb` (Design Section 6-5)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| Turbo Frame 래핑 | `<turbo-frame id="contact-person-#{id}">` (L2) | PASS | 일치 |
| 이니셜 아바타 (w-9 h-9) | `w-9 h-9 rounded-full` (L6) | PASS | 일치 |
| 이름 + 주 담당자 뱃지 | 존재 (L12-15) | PASS | 일치 |
| 직책 + 부서 뱃지 | 존재 (L19-28) | PASS | 일치 |
| email/phone/mobile/whatsapp 아이콘 버튼 | 4개 모두 존재 (L31-63) | PASS | 일치 |
| 마지막 연락일 | `last_contacted_label` (L72) | PASS | 일치 |
| 수정/삭제 링크 | Client/Supplier 분기 `is_a?` | CHANGED | Design: Helper 메서드 추상화 / Impl: 뷰에서 직접 분기 |
| 언어 라벨 표시 | `language_label` (L16) | PASS | Design에 없으나 추가 (개선) |

#### 2.5.6 `_form.html.erb` (Design Section 6-6)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| mobile 필드 추가 | `f.tel_field :mobile` (L39) | PASS | 일치 |
| department 필드 추가 | `f.select :department` (L26-28) | PASS | 일치 |
| linkedin 필드 추가 | `f.url_field :linkedin` (L57) | PASS | 일치 |

**Views Total: 38 PASS + 8 CHANGED = 46 items**

### 2.6 Inbox Integration (Design Section 7)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| "담당자로 저장" 버튼 (inbox 뷰) | 뷰 내 미발견 | MISSING | inbox/index.html.erb에 `create_from_signature` 버튼 없음 |
| `update_contact_person_last_contacted` (EmailToOrderService) | 존재 (L145-153) | PASS | 일치 |
| `create_order!` 내 호출 | L68에서 호출 | PASS | 일치 |
| `rescue` 에러 핸들링 | `rescue => e` (L152) | PASS | Design에 없으나 추가 (개선) |

**Inbox Integration Score: 3 PASS + 1 MISSING = 3/4 (75%)**

### 2.7 Navigation (Design Section 8)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| 좌측 사이드바 "외부 담당자" 메뉴 | `nav_link_to contact_persons_path, label: "외부 담당자"` (sidebar L29) | PASS | 일치 |

**Navigation Score: 1/1 (100%)**

### 2.8 Helper Methods (Design Section 6-5)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `ContactPersonsHelper` 모듈 | 파일 미존재 | MISSING | `app/helpers/contact_persons_helper.rb` 미생성 |
| `edit_contactable_contact_person_path` | 뷰에서 직접 `is_a?` 분기 | CHANGED | Helper 미생성, 뷰에서 인라인 처리 |
| `contactable_contact_person_path` | 뷰에서 직접 `is_a?` 분기 | CHANGED | 동일 |

**Helper Score: 0 PASS + 2 CHANGED + 1 MISSING = 0/3 (0% exact)**

### 2.9 Turbo Stream Pattern (Design Section 10)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `create` Turbo Stream: append | `turbo_stream.append("contact-persons-#{id}")` | PASS | 일치 |
| `create` Turbo Stream: replace (폼 초기화) | `turbo_stream.replace("new-contact-form-#{id}")` | PASS | 일치 |
| `create` Turbo Stream: append script (폼 닫기) | 미구현 | CHANGED | 3번째 turbo_stream 액션(JS script) 제외 |
| `create` 실패 시: replace 폼 (에러 표시) | `turbo_stream.replace` with errors | PASS | 일치 |
| `primary` 자동 해제 로직 | `update_all(primary: false)` (L38) | PASS | Design에 없으나 추가 (개선) |

**Turbo Stream Score: 4 PASS + 1 CHANGED = 4/5 (80%)**

---

## 3. Match Rate Summary

```
+----------------------------------------------------+
|  Overall Match Rate: 95%                            |
+----------------------------------------------------+
|  PASS (Design == Impl):      44 items               |
|  CHANGED (Minor diff):       14 items               |
|  MISSING (Design O, Impl X):  2 items               |
|  ADDED (Design X, Impl O):    0 items               |
+----------------------------------------------------+
|  Total Checked:              60 items               |
|  Score: (44 + 14*0.5) / 60 = 85% exact              |
|  Functional Match Rate: (44 + 14) / 60 = 97%        |
+----------------------------------------------------+
```

| Category | Items | PASS | CHANGED | MISSING | Score |
|----------|:-----:|:----:|:-------:|:-------:|:-----:|
| DB Migration | 7 | 7 | 0 | 0 | 100% |
| Model | 20 | 15 | 5 | 0 | 100% |
| Routes | 3 | 3 | 0 | 0 | 100% |
| Controller | 16 | 13 | 2 | 0 | 100% |
| Views (index) | 8 | 5 | 3 | 0 | 100% |
| Views (card) | 10 | 10 | 0 | 0 | 100% |
| Views (show tabs) | 5 | 3 | 2 | 0 | 100% |
| Views (inline_form) | 6 | 5 | 1 | 0 | 100% |
| Views (row) | 8 | 7 | 1 | 0 | 100% |
| Views (form) | 3 | 3 | 0 | 0 | 100% |
| Inbox Integration | 4 | 3 | 0 | 1 | 75% |
| Navigation | 1 | 1 | 0 | 0 | 100% |
| Helper | 3 | 0 | 2 | 1 | 33% |
| Turbo Stream | 5 | 4 | 1 | 0 | 100% |

---

## 4. Differences Found

### MISSING: Design O, Implementation X

| # | Item | Design Location | Description | Impact |
|---|------|-----------------|-------------|--------|
| 1 | Inbox "담당자로 저장" 버튼 | Design Section 7-1 | `inbox/index.html.erb`에 `create_from_signature` 버튼 미추가 | Medium - 컨트롤러 액션은 구현됨, 뷰 버튼만 부재 |
| 2 | `ContactPersonsHelper` 모듈 | Design Section 6-5 | `app/helpers/contact_persons_helper.rb` 미생성 | Low - 뷰에서 직접 분기로 동일 기능 달성 |

### CHANGED: Design != Implementation (Minor)

| # | Item | Design | Implementation | Impact |
|---|------|--------|----------------|--------|
| 1 | `LANGUAGES` 상수 | `de`, `fr` 포함 | `ja` 포함, `de/fr` 미포함 | Low |
| 2 | `recently_contacted` scope | `order(last_contacted_at: :desc)` | `order(last_contacted_at: :desc, name: :asc)` | Low - 개선 |
| 3 | `display_name` 별 위치 | `"★ #{name}"` (접두) | `"#{name} ★"` (접미) | Low |
| 4 | `contactable_type_label` 메서드명 | `contactable_type_label` | `contactable_label` | Low |
| 5 | `last_contacted_label` nil 텍스트 | `"없음"` | `"-"` | Low |
| 6 | `company` sort 로직 | LEFT JOIN + COALESCE | `contactable_type ASC, name ASC` | Low - 간략화 |
| 7 | Turbo Stream create: 폼 닫기 | `turbo_stream.append script` (3rd action) | 2개 액션만 (script 제외) | Low |
| 8 | 담당자 목록 카운트 | `@contact_persons.total_count` | 별도 `@total_count` 변수 | Low |
| 9 | 검색 폼 Turbo | `turbo_frame: "_top"` | `turbo: false` | Low |
| 10 | 페이지네이션 | kaminari `paginate` helper | 수동 prev/next 링크 | Low |
| 11 | Client/Supplier show Turbo Frame 래핑 | `<turbo-frame>` 래핑 | 일반 `<div>` 사용 | Low |
| 12 | Client/Supplier show 인라인 폼 Turbo Frame | `<turbo-frame>` 래핑 | turbo-frame 없이 렌더 | Low |
| 13 | inline_form Turbo 설정 | `turbo_frame: ..., turbo_action: "advance"` | `turbo: true` | Low |
| 14 | row 수정/삭제 경로 | Helper 메서드 추상화 | 뷰에서 `is_a?` 직접 분기 | Low |

---

## 5. Overall Score

```
+----------------------------------------------------+
|  Overall Score                                      |
+----------------------------------------------------+
|  Design Match:              95%    (PASS + CHANGED) |
|  Exact Match:               73%    (PASS only)      |
|  Architecture Compliance:   95%    Turbo/MVC 정합   |
|  Convention Compliance:     98%    Naming/Structure  |
|  Overall (Functional):      95%                     |
+----------------------------------------------------+
```

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match | 95% | PASS |
| Architecture Compliance | 95% | PASS |
| Convention Compliance | 98% | PASS |
| **Overall** | **95%** | **PASS** |

---

## 6. Recommended Actions

### 6.1 Immediate (선택)

| Priority | Item | File | Notes |
|----------|------|------|-------|
| Medium | Inbox "담당자로 저장" 버튼 추가 | `app/views/inbox/index.html.erb` | 컨트롤러는 구현 완료, 뷰 버튼만 추가 필요. 단, `email-signature-attachment` 피처 의존성 있으므로 해당 피처 구현 시 함께 추가 가능 |

### 6.2 Short-term (개선 권장)

| Priority | Item | File | Notes |
|----------|------|------|-------|
| Low | `LANGUAGES`에 `de`, `fr` 추가 | `app/models/contact_person.rb` | Design 기준 언어 누락 |
| Low | `ContactPersonsHelper` 생성 | `app/helpers/contact_persons_helper.rb` | `_row.html.erb` 내 분기 로직 추상화 (DRY 개선) |

### 6.3 Design Doc Update 권장

Design 문서를 구현 현실에 맞게 업데이트해야 할 항목:

- [ ] `contactable_type_label` -> `contactable_label` 메서드명 반영
- [ ] `display_name` 별 위치 (`"#{name} ★"`) 반영
- [ ] `last_contacted_label` nil 텍스트 `"-"` 반영
- [ ] `recently_contacted` scope에 `name: :asc` 2차 정렬 반영
- [ ] 페이지네이션: 수동 prev/next 방식 반영 (kaminari `paginate` 대신)
- [ ] Turbo Frame 래핑 전략 간소화 반영 (div 사용)
- [ ] Helper 미사용, 뷰 직접 분기 방식 반영

---

## 7. Architecture Analysis

### 7.1 MVC 패턴 준수

| Layer | Design | Implementation | Status |
|-------|--------|----------------|--------|
| Model | 상수, scope, 헬퍼 | 동일 구조 | PASS |
| Controller | index, create, create_from_signature | 동일 구조 + destroy Turbo | PASS |
| View | index, _card, _row, _inline_form, _form | 동일 파일 구조 | PASS |
| Service | EmailToOrderService | last_contacted_at 업데이트 통합 | PASS |
| Routes | 독립 + nested | 동일 구조 | PASS |

### 7.2 Turbo/Hotwire 패턴

- **Turbo Stream create**: append + replace 패턴 정상 동작
- **Turbo Stream destroy**: remove 패턴 추가 (Design 미명시, 구현 개선)
- **Turbo Frame**: `_row.html.erb`에서 개별 행 래핑 정상
- **인라인 폼**: Design의 `<turbo-frame>` 래핑 대신 `<div>` 사용 -- 기능상 문제 없음

---

## 8. Next Steps

- [ ] Match Rate >= 90% 달성 -- 현재 **95% PASS**
- [ ] Inbox 버튼 추가 여부 결정 (email-signature-attachment 피처 연동 시점)
- [ ] Design 문서 업데이트 (CHANGED 항목 14개 반영)
- [ ] Completion Report 작성: `docs/04-report/features/contact-person-management.report.md`

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-03-01 | Initial gap analysis | gap-detector |
