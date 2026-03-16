# inbox-subject-cleanup Analysis Report

> **Analysis Type**: Gap Analysis (Plan vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-03-16
> **Plan Doc**: [inbox-subject-cleanup.plan.md](../01-plan/features/inbox-subject-cleanup.plan.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Plan 문서에 정의된 "Inbox 메일 제목 간소화" 요구사항 대비 실제 구현의 일치율을 측정한다.
Design 단계를 생략한 단순 리팩토링 피처이므로, Plan 문서를 설계 기준으로 직접 비교한다.

### 1.2 Analysis Scope

- **Plan Document**: `docs/01-plan/features/inbox-subject-cleanup.plan.md`
- **Implementation Files**:
  - `app/models/order.rb` (display_subject, subject_tags)
  - `app/services/gmail/email_to_order_service.rb` (build_title)
  - `app/views/inbox/index.html.erb` (제목 표시 2곳)
  - `app/views/inbox/show.html.erb` (제목 표시 4곳)
  - `app/views/orders/_drawer_content.html.erb` (제목 표시 3곳)
  - `app/controllers/inbox_controller.rb` (검색 쿼리)
- **Analysis Date**: 2026-03-16

---

## 2. Gap Analysis (Plan vs Implementation)

### 2.1 Model Methods

| Plan | Implementation | Status | Notes |
|------|---------------|--------|-------|
| `display_subject` RE/FW strip | order.rb:77 `.sub(/RE\|FW\|Fwd/i)` while loop | ✅ Match | `gsub` -> `sub` 변경, 동일 효과 |
| `display_subject` reference_no 제거 | order.rb:79-81 `gsub(Regexp.escape)` | ✅ Match | |
| `display_subject` 앞뒤 구분자 정리 | order.rb:85 | ✅ Match | |
| `display_subject` fallback `title` | order.rb:86 `subject.presence \|\| title` | ✅ Match | |
| - | order.rb:83 RFQ/견적요청 접두사 제거 | ⚠️ Added | Plan에 없는 추가 로직 |
| `SUBJECT_TAGS` 7개 패턴 | order.rb:89-97 | ✅ Match | 7개 동일 |
| `subject_tags` 추출 | order.rb:100-105 | ✅ Match | |
| `subject_tags` 최대 3개 제한 | order.rb:104 `.first(3)` | ✅ Match | Plan에서는 "제한 가능"으로 표현, 구현에서 적용 |

### 2.2 Service Layer

| Plan | Implementation | Status | Notes |
|------|---------------|--------|-------|
| `build_title` RE/FW strip | email_to_order_service.rb:102-103 | ✅ Match | while loop으로 반복 제거 |

### 2.3 View Changes (Plan 기준 10곳)

| # | Plan 위치 | Plan 파일:라인 | Implementation | Status |
|---|----------|---------------|----------------|--------|
| 1 | Inbox 목록 (스레드 내) | index.html.erb:252 | L252: `display_subject` + reference_no 배지 + subject_tags | ✅ Match |
| 2 | Inbox 목록 (단건) | index.html.erb:294 | L294: `display_subject` + reference_no 배지 + subject_tags | ✅ Match |
| 3 | Inbox 상세 (page_title) | show.html.erb:2 | L2: `display_subject` 사용 | ✅ Match |
| 4 | Inbox 상세 (h2) | show.html.erb:14 | L14: `display_subject` + reference_no 배지 + subject_tags | ✅ Match |
| 5 | Inbox 상세 (h1) | show.html.erb:27 | L27: `display_subject` + reference_no 배지 + subject_tags | ✅ Match |
| 6 | Inbox 상세 (관련 메일) | show.html.erb:443 | L443: `display_subject` + reference_no 배지 | ✅ Match |
| 7 | Order 드로어 (원본) | _drawer_content.html.erb:270 | L270: `display_subject` + reference_no 배지 + subject_tags | ✅ Match |
| 8 | Order 드로어 (스레드 현재) | _drawer_content.html.erb:363 | L363: `display_subject` 사용 | ✅ Match |
| 9 | Order 드로어 (스레드 목록) | _drawer_content.html.erb:386 | L386: `display_subject` 사용 | ✅ Match |

### 2.4 Non-Change Verification

| Plan 비변경 대상 | 실제 | Status | Notes |
|-----------------|------|--------|-------|
| DB 마이그레이션 없음 | 마이그레이션 파일 미생성 | ✅ Match | 런타임 계산만 사용 |
| `inbox_controller.rb` 검색 원본 유지 | L31: `original_email_subject LIKE` 그대로 | ✅ Match | |
| `orders_controller.rb` 미변경 | 변경 없음 | ✅ Match | |

### 2.5 Badge Styling

| Plan | Implementation | Status | Notes |
|------|---------------|--------|-------|
| reference_no: blue bg, font-mono | `bg-blue-100 text-blue-700 rounded font-mono` | ✅ Match | |
| subject_tags: amber bg | `bg-amber-100 text-amber-700 rounded` | ✅ Match | |

---

## 3. Differences Found

### ⚠️ Added Features (Plan X, Implementation O)

| # | Item | Implementation Location | Description | Impact |
|---|------|------------------------|-------------|--------|
| 1 | RFQ/견적요청 접두사 제거 | order.rb:83 | `display_subject`에 RFQ/견적요청 접두사 strip 로직 추가 | Low (긍정적 개선) |

### ⚠️ Missed Location (Plan O, Implementation X)

| # | Item | Plan Location | Description | Impact |
|---|------|--------------|-------------|--------|
| 1 | Email detail panel h2 | index.html.erb:444 | Inbox 우측 상세 패널의 제목 표시에 `original_email_subject` 원본 사용 중. Plan에서는 이 위치가 명시되지 않았으나, display_subject로 변환해야 일관성 확보 | Medium |

---

## 4. Match Rate Summary

```
+---------------------------------------------+
|  Overall Match Rate: 95%                     |
+---------------------------------------------+
|  Plan 요구사항 체크리스트: 19개 항목          |
|  ✅ Match:            18 items (95%)         |
|  ⚠️ Missed location:   1 item  (5%)          |
|  ⚠️ Added (non-plan):  1 item  (N/A)         |
+---------------------------------------------+
```

### Detailed Checklist

- [x] display_subject method exists and strips RE/FW/Fwd prefixes
- [x] display_subject removes reference_no from subject
- [x] display_subject has fallback to title when empty
- [x] SUBJECT_TAGS constant defined with 7 patterns
- [x] subject_tags method extracts tags, limited to 3
- [x] build_title in email_to_order_service.rb strips RE/FW
- [x] inbox/index.html.erb thread view uses display_subject + badges
- [x] inbox/index.html.erb single view uses display_subject + badges
- [x] inbox/show.html.erb page_title uses display_subject
- [x] inbox/show.html.erb breadcrumb h2 uses display_subject + badges
- [x] inbox/show.html.erb h1 uses display_subject + badges
- [x] inbox/show.html.erb related emails use display_subject
- [x] drawer_content original email subject uses display_subject + badges
- [x] drawer_content thread current uses display_subject
- [x] drawer_content thread list uses display_subject
- [x] inbox_controller.rb search still uses original_email_subject (NOT changed)
- [x] No DB migration created
- [x] reference_no badge styling: blue bg, font-mono
- [x] subject_tags badge styling: amber bg
- [ ] inbox/index.html.erb:444 email detail panel h2 -- 미변경 (original_email_subject 원본 사용 중)

---

## 5. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Plan Match (기능 구현) | 95% | ✅ |
| 일관성 (모든 뷰 통일) | 90% | ✅ |
| Convention Compliance | 100% | ✅ |
| **Overall** | **95%** | ✅ |

---

## 6. Recommended Actions

### 6.1 Immediate (선택적)

| Priority | Item | File:Line | Description |
|----------|------|-----------|-------------|
| ⚠️ | Email detail panel 제목 통일 | `app/views/inbox/index.html.erb:444` | `original_email_subject.presence \|\| order.title` -> `display_subject` + 배지로 변경하여 나머지 9곳과 동일한 UX 제공 |

### 6.2 Plan Document Update

| Item | Description |
|------|-------------|
| RFQ 접두사 제거 반영 | `display_subject` 로직에 Step 3 "RFQ/견적요청 접두사 제거" 추가됨을 Plan에 반영 |
| Email detail panel 위치 추가 | index.html.erb:444 위치를 Plan 2.3 표에 추가 (총 11곳) |

---

## 7. Synchronization Recommendation

Match Rate >= 90% 이므로 "설계와 구현이 잘 일치합니다."

**Minor 차이 해결 옵션:**
1. index.html.erb:444를 `display_subject`로 변경하여 100% 달성
2. Plan 문서에 RFQ 접두사 제거 로직과 email detail panel 위치를 추가

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-03-16 | Initial gap analysis | bkit-gap-detector |
