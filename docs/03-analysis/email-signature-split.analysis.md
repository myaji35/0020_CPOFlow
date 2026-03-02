# email-signature-split Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Version**: Phase 4
> **Analyst**: Claude Code (gap-detector)
> **Date**: 2026-03-02
> **Design Doc**: Inline design specification (user request)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

이메일 본문에서 서명 영역을 시각적으로 분리하는 `email-signature-split` 피처의 설계 요구사항과 실제 구현 코드 간의 일치도를 검증한다.

### 1.2 Analysis Scope

- **Design Document**: User 설계 요구사항 (inline)
- **Implementation Files**:
  - `app/services/gmail/email_signature_parser_service.rb`
  - `app/models/order.rb`
  - `app/views/inbox/show.html.erb`
  - `app/views/inbox/index.html.erb`
- **Analysis Date**: 2026-03-02

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 Service Layer — EmailSignatureParserService

| # | Design Requirement | Implementation | Status | Location |
|---|-------------------|----------------|:------:|----------|
| S1 | `split` 클래스 메서드 추가 | `self.split(plain_body, html_body = nil)` | PASS | L36-38 |
| S2 | `split`이 `{ body:, signature: }` Hash 반환 | `{ body: ..., signature: ... }` 반환 | PASS | L49-56 |
| S3 | `find_delimiter_index` private 메서드로 리팩터링 | `def find_delimiter_index(lines)` private 메서드 존재 | PASS | L90-96 |
| S4 | `--`, `Best regards,`, `감사합니다` 등 구분자 패턴 감지 | `SIGNATURE_DELIMITERS` 상수에 5개 패턴 정의 | PASS | L13-19 |
| S5 | `extract_signature_block`이 `find_delimiter_index` 재활용 | L100에서 `find_delimiter_index(lines)` 호출 | PASS | L98-109 |
| S6 | 서명 없는 경우 `{ body: original, signature: nil }` 반환 | `{ body: @plain_body, signature: nil }` 반환 | PASS | L55 |

### 2.2 Model Layer — Order

| # | Design Requirement | Implementation | Status | Location |
|---|-------------------|----------------|:------:|----------|
| M1 | `body_without_signature` 편의 메서드 | `Gmail::EmailSignatureParserService.split(...)[:body]` 반환 | PASS | L117-121 |
| M2 | `signature_block_text` 편의 메서드 | `Gmail::EmailSignatureParserService.split(...)[:signature]` 반환 | PASS | L124-128 |

### 2.3 View Layer — show.html.erb

| # | Design Requirement | Implementation | Status | Location |
|---|-------------------|----------------|:------:|----------|
| V1 | HTML 우선 렌더링 (sanitize) | `<% if html_body.present? %>` 분기 + `sanitize()` 호출 | PASS | L134-141 |
| V2 | sanitize()에 허용 태그/속성 명시 | `tags: %w[p br div span a b i u strong em h1-h6 ul ol li table ... img hr]`, `attributes: %w[href src alt style class target rel]` | PASS | L138-140 |
| V3 | Plain text fallback: 본문/서명 분리 | `Gmail::EmailSignatureParserService.split(plain_body)` 호출 | PASS | L144 |
| V4 | 서명 분리 카드 UI (dashed border) | `border-t border-dashed border-gray-200` | PASS | L150 |
| V5 | 가위 아이콘 | SVG scissors icon (circle + path 패턴) | PASS | L152 |
| V6 | "발신자 서명" 라벨 | `<span class="text-xs ... uppercase ...">발신자 서명</span>` | PASS | L153 |
| V7 | `.email-html-body` CSS 스타일 추가 | `<style>` 블록에 7개 CSS 규칙 정의 (font-size, link color, img, table, blockquote, dark mode) | PASS | L122-129 |
| V8 | max-h-96 overflow-y-auto 스크롤 영역 | HTML: `max-h-96 overflow-y-auto`, Plain text: `max-h-96 overflow-y-auto` | PASS | L136, L145 |

### 2.4 View Layer — index.html.erb (3-pane)

| # | Design Requirement | Implementation | Status | Location |
|---|-------------------|----------------|:------:|----------|
| I1 | plain text fallback에 서명 분리 카드 UI 추가 | `Gmail::EmailSignatureParserService.split(plain_body)` 호출 + 동일 UI 패턴 | PASS | L537-551 |
| I2 | HTML 렌더링 (이미 존재, 수정 불필요) | `sanitize(html_body, tags: ..., attributes: ...)` | PASS | L531-534 |
| I3 | `.email-html-body` CSS 스타일 | `<style>` 블록에 동일 CSS 규칙 정의 | PASS | L31-37 |
| I4 | 서명 분리 카드: dashed border + 가위 아이콘 + "발신자 서명" 라벨 | show.html.erb와 동일한 패턴으로 구현 | PASS | L542-549 |

### 2.5 Match Rate Summary

```
+---------------------------------------------+
|  Overall Match Rate: 100%                    |
+---------------------------------------------+
|  PASS (Match):        18 items (100%)        |
|  CHANGED:              0 items (0%)          |
|  MISSING (Design O):   0 items (0%)          |
|  ADDED (Design X):     0 items (0%)          |
+---------------------------------------------+
```

---

## 3. Detailed Verification

### 3.1 `split` 메서드 동작 검증

**구분자 패턴 (SIGNATURE_DELIMITERS):**

| # | Pattern | Example Match | Verified |
|---|---------|--------------|:--------:|
| 1 | `/^--\s*$/` | `--` (standalone) | PASS |
| 2 | `/^_{3,}$/` | `___` | PASS |
| 3 | `/^-{3,}$/` | `---` | PASS |
| 4 | `/^(Best regards\|Kind regards\|..)[,\s]*$/i` | `Best regards,` | PASS |
| 5 | `/^(감사합니다\|안녕히\s*계세요\|드림)[,\s.]*$/` | `감사합니다.` | PASS |

**반환값 검증:**

```ruby
# 구분자가 있는 경우
Gmail::EmailSignatureParserService.split("Hello\n\n--\nJohn Kim\nSales Manager")
# => { body: "Hello", signature: "--\nJohn Kim\nSales Manager" }

# 구분자가 없는 경우
Gmail::EmailSignatureParserService.split("Hello world")
# => { body: "Hello world", signature: nil }
```

### 3.2 Order 모델 편의 메서드 검증

```ruby
# body_without_signature — split[:body] 위임
order.body_without_signature
# => Gmail::EmailSignatureParserService.split(order.original_email_body, order.original_email_html_body)[:body]

# signature_block_text — split[:signature] 위임
order.signature_block_text
# => Gmail::EmailSignatureParserService.split(order.original_email_body, order.original_email_html_body)[:signature]
```

### 3.3 보안: sanitize 허용 목록

| Category | Allowed | Notes |
|----------|---------|-------|
| Tags | `p, br, div, span, a, b, i, u, strong, em, h1-h6, ul, ol, li, table, thead, tbody, tr, th, td, blockquote, pre, code, img, hr` | XSS 위험 태그 (script, iframe, form, input) 제외됨 |
| Attributes | `href, src, alt, style, class, target, rel` | onclick 등 이벤트 핸들러 제외됨 |

보안 수준: 적절함. `style` 속성은 Rails sanitize helper가 위험한 CSS (expression, url 등)를 자동 필터링.

### 3.4 UI 일관성 검증

| UI Element | show.html.erb | index.html.erb | Consistent |
|-----------|--------------|----------------|:----------:|
| border-dashed 구분선 | `border-t border-dashed border-gray-200 dark:border-gray-600` | `border-t border-dashed border-gray-200 dark:border-gray-600` | PASS |
| 가위 아이콘 SVG | scissors SVG (circle + path) | 동일 SVG | PASS |
| "발신자 서명" 라벨 | `text-xs uppercase tracking-wider font-semibold` | 동일 클래스 | PASS |
| 서명 배경 카드 | `bg-gray-50/80 dark:bg-gray-700/20 rounded-lg p-4` | 동일 스타일 | PASS |
| dark mode 지원 | dark: 접두사 포함 | dark: 접두사 포함 | PASS |

---

## 4. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match | 100% | PASS |
| Architecture Compliance | 100% | PASS |
| Convention Compliance | 100% | PASS |
| **Overall** | **100%** | **PASS** |

---

## 5. Differences Found

### MISSING Features (Design O, Implementation X)

_None_

### ADDED Features (Design X, Implementation O)

_None_

### CHANGED Features (Design != Implementation)

_None_

---

## 6. Code Quality Notes

### 6.1 DRY (Don't Repeat Yourself)

- `find_delimiter_index`가 `split`과 `extract_signature_block` 양쪽에서 재활용됨: 중복 제거 완료
- show.html.erb와 index.html.erb에서 서명 분리 카드 UI 패턴이 동일: 일관성 확보 (partial 추출은 추후 리팩토링 가능)

### 6.2 Edge Cases

| Case | Handling | Status |
|------|---------|:------:|
| plain_body가 nil | `.to_s`로 빈 문자열 변환 | PASS |
| html_body가 nil | `html_body = nil` 기본값 | PASS |
| 구분자 없는 이메일 | `signature: nil` 반환 | PASS |
| 빈 서명 블록 | `split[:signature].present?` 체크 후 UI 조건부 렌더링 | PASS |

---

## 7. Recommended Actions

### Immediate Actions

_None required_ -- 설계와 구현이 100% 일치함.

### Future Improvements (Optional)

1. **Partial 추출**: show.html.erb와 index.html.erb의 서명 분리 카드 UI를 `_signature_card.html.erb` partial로 추출하면 유지보수성 향상
2. **CSS 중복**: `.email-html-body` 스타일이 두 파일 모두에 인라인 `<style>` 태그로 존재. 공통 stylesheet로 이동 권장 (TailwindCSS CDN 환경에서는 현 방식도 허용)
3. **Caching**: `body_without_signature`와 `signature_block_text`가 각각 `split`을 호출하므로, 두 메서드를 동시 호출 시 파싱이 2회 발생. 필요시 memoization 패턴 적용 가능

---

## 8. Next Steps

- [x] Gap Analysis 완료
- [ ] Completion Report 작성 (`/pdca report email-signature-split`)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-03-02 | Initial analysis — 100% match | gap-detector |
