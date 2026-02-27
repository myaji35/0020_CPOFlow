# order-form-autocomplete Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: CPOFlow
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-28
> **Design Doc**: [order-form-autocomplete.design.md](../02-design/features/order-form-autocomplete.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Design 문서(`order-form-autocomplete.design.md`)에 정의된 API Endpoints, Stimulus Controller, ERB Widget 패턴이 실제 구현과 일치하는지 검증한다.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/order-form-autocomplete.design.md`
- **Implementation Files**:
  - `config/routes.rb` (lines 78-93)
  - `app/controllers/clients_controller.rb` (search action, line 100-106)
  - `app/controllers/suppliers_controller.rb` (search action, line 90-96)
  - `app/controllers/projects_controller.rb` (search action, line 62-68)
  - `app/javascript/controllers/autocomplete_controller.js` (203 lines)
  - `app/views/orders/_form.html.erb` (163 lines)

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 API Endpoints

| # | Design | Implementation | Status | Notes |
|:-:|--------|---------------|:------:|-------|
| 1 | `GET /clients/search?q=...` | `GET /clients/search?q=...` (collection route) | PASS | routes.rb:79, controller:100 |
| 2 | Response: `[{ id, name, code, country }]` | `[{ id, name, code, country }]` | PASS | controller:104 -- 필드 4개 정확 일치 |
| 3 | max 10 | `.limit(10)` | PASS | controller:104 |
| 4 | Auth: require_login | `before_action :authenticate_user!` | PASS | controller:2 |
| 5 | `GET /suppliers/search?q=...` | `GET /suppliers/search?q=...` (collection route) | PASS | routes.rb:85, controller:90 |
| 6 | Response: `[{ id, name, code, industry }]` | `[{ id, name, code: ecount_code, industry: industry_label }]` | CHANGED | Design `code` -> impl `ecount_code`, Design `industry` -> impl `industry_label` (아래 상세) |
| 7 | max 10 | `.limit(10)` | PASS | controller:94 |
| 8 | `GET /projects/search?q=...` | `GET /projects/search?q=...` (collection route) | PASS | routes.rb:92, controller:62 |
| 9 | Response: `[{ id, name, client_name, status }]` | `[{ id, name, client_name, status }]` | PASS | controller:66 -- 필드 4개 정확 일치 |
| 10 | max 10 | `.limit(10)` | PASS | controller:65 |

**API Endpoint Summary**: 10개 항목 중 9 PASS, 1 CHANGED = **90%**

#### Changed Item Detail

| # | Item | Design | Implementation | Impact |
|:-:|------|--------|----------------|--------|
| 6 | Supplier search response `code` field | `code` (model field) | `ecount_code` (key: `code`) | Low -- JSON key는 `code`로 동일하나, 실제 매핑 소스가 `s.ecount_code`임 |
| 6 | Supplier search response `industry` field | `industry` (raw enum) | `industry_label` (human-readable) | Low -- JSON key는 `industry`로 동일하나, 값이 enum 대신 레이블 |

> Note: JSON 응답의 **키 이름**은 Design과 동일(`code`, `industry`)하지만, **값의 소스**가 다릅니다. Supplier 모델에는 `code` 필드가 없고 `ecount_code`를 사용하며, `industry_label`은 enum의 human-readable 텍스트입니다. 이는 Design 작성 시점과 실제 모델 구조 차이에서 비롯된 합리적 변경입니다.

---

### 2.2 Stimulus Controller

| # | Design Spec | Implementation | Status | Notes |
|:-:|-------------|---------------|:------:|-------|
| 1 | Values: `url(String)` | `url: String` | PASS | controller.js:9 |
| 2 | Values: `placeholder(String)` | `placeholder: { type: String, default: "검색..." }` | PASS | controller.js:10, default 추가됨 (호환) |
| 3 | Values: `labelField(String="name")` | `sublabel: { type: String, default: "code" }` | CHANGED | Design은 `labelField`(주 레이블 키), impl은 `sublabel`(부 레이블 키). 이름과 용도가 다름 |
| 4 | Targets: `input, hidden, dropdown, badge, container` | `input, hidden, dropdown, badge, badgeLabel, badgeSub` | CHANGED | `container` 없음, `badgeLabel`/`badgeSub` 추가 |
| 5 | `connect()`: hiddenValue -> fetchInitial(id) -> badge | hidden에 값 -> `_fetchInitial(id)` -> `_showBadge(item)` | PASS | controller.js:22-24 |
| 6 | `connect()`: input에 debounce 이벤트 등록 | ERB에서 `data-action="input->autocomplete#onInput"` 으로 위임 | PASS | Stimulus 관례상 connect에서 등록 안하고 action descriptor 사용은 동치 |
| 7 | `onInput(e)`: q < 1 -> closeDropdown | `q.length < 1 -> _closeDropdown()` | PASS | controller.js:42-44 |
| 8 | `onInput(e)`: debounce 300ms -> fetchResults | `setTimeout(() => _fetchResults(q), 300)` | PASS | controller.js:46 |
| 9 | `fetchResults(q)`: fetch URL+q | `fetch(urlValue?q=encodeURI(q))` | PASS | controller.js:85 |
| 10 | `fetchResults(q)`: renderDropdown(results) | `_renderDropdown(data)` | PASS | controller.js:89 |
| 11 | `selectItem(id, label, sublabel)` | `_select(id, label, sub)` | PASS | controller.js:165 -- 동일 로직, 메서드명만 다름 |
| 12 | `selectItem`: hiddenTarget.value = id | `this.hiddenTarget.value = id` | PASS | controller.js:166 |
| 13 | `selectItem`: badge 표시 (label + sublabel + X) | `_showBadge()` -> badgeLabel + badgeSub + clear 버튼 | PASS | controller.js:171-178 |
| 14 | `selectItem`: input 숨김 | `inputTarget.classList.add("hidden")` | PASS | controller.js:176 |
| 15 | `selectItem`: dropdown 닫기 | `_closeDropdown()` | PASS | controller.js:168 |
| 16 | `clearSelection()`: hidden="" | `this.hiddenTarget.value = ""` | PASS | controller.js:74 |
| 17 | `clearSelection()`: badge 숨김 | `badgeTarget.classList.add("hidden")` | PASS | controller.js:75 |
| 18 | `clearSelection()`: input 재노출 + focus | `inputTarget.classList.remove("hidden"); inputTarget.focus()` | PASS | controller.js:76-78 |
| 19 | Keyboard: Arrow Up/Down -> 포커스 이동 | `onKeydown`: ArrowDown/ArrowUp -> `_highlight(items)` | PASS | controller.js:54-61 |
| 20 | Keyboard: Enter -> 선택 | `e.key === "Enter" -> items[highlighted].click()` | PASS | controller.js:62-65 |
| 21 | Keyboard: Escape -> 닫기 | `e.key === "Escape" -> _closeDropdown()` | PASS | controller.js:67-68 |
| 22 | 외부클릭: dropdown 닫기 | `document.addEventListener("click", _outsideClick)` | PASS | controller.js:27-30 |

**Stimulus Controller Summary**: 22개 항목 중 20 PASS, 2 CHANGED = **91%**

#### Changed Item Details

| # | Item | Design | Implementation | Impact |
|:-:|------|--------|----------------|--------|
| 3 | Value 이름/용도 | `labelField(String="name")` -- 주 레이블 렌더링 키 | `sublabel(String="code")` -- 부 레이블 렌더링 키 | Low -- impl은 주 레이블을 항상 `name`으로 고정하고, sublabel만 설정 가능하게 함. 더 단순한 설계. |
| 4 | Targets 구성 | `input, hidden, dropdown, badge, container` | `input, hidden, dropdown, badge, badgeLabel, badgeSub` | Low -- `container` 불필요 (element 자체가 container). badge를 `badgeLabel`+`badgeSub`로 세분화하여 DOM 조작 효율화. |

> Note: 두 변경 모두 Design 대비 **기능적으로 동등하거나 개선**된 방향입니다. `sublabel` Value는 Design의 `labelField` 보다 명확한 역할 분리이며, Target 세분화는 badge 내부를 innerHTML 대신 textContent로 업데이트하여 XSS 안전성을 높입니다.

---

### 2.3 ERB Widget Pattern

| # | Design Spec | Implementation | Status | Notes |
|:-:|-------------|---------------|:------:|-------|
| 1 | `data-controller="autocomplete"` | 3곳 모두 `data-controller="autocomplete"` | PASS | _form.html.erb:18,59,87 |
| 2 | `data-autocomplete-url-value="/clients/search"` | `search_clients_path` (= `/clients/search`) | PASS | _form.html.erb:19 |
| 3 | `data-autocomplete-placeholder-value="발주처 검색..."` | `"발주처 검색..."` | PASS | _form.html.erb:20 |
| 4 | `<input type="hidden" name="order[client_id]">` | `f.hidden_field :client_id, data: { autocomplete_target: "hidden" }` | PASS | _form.html.erb:23 |
| 5 | badge, input, dropdown targets | badge + badgeLabel + badgeSub + input + dropdown targets | PASS | _form.html.erb:25-44 |
| 6 | Client autocomplete widget | 완전한 위젯 구현 | PASS | _form.html.erb:17-46 |
| 7 | Supplier autocomplete widget | 완전한 위젯 구현 | PASS | _form.html.erb:57-83 |
| 8 | Project autocomplete widget | 완전한 위젯 구현 | PASS | _form.html.erb:86-112 |
| 9 | 3개 select -> autocomplete 교체 | 기존 `<select>` 태그 없음, 모두 autocomplete 위젯 | PASS | 기존 select 완전히 제거됨 |
| 10 | X 버튼으로 선택 해제 | `data-action="click->autocomplete#clear"` + SVG X icon | PASS | _form.html.erb:29-32,69-72,97-100 |

**ERB Widget Summary**: 10개 항목 전체 PASS = **100%**

---

### 2.4 File List Verification

| Design File List | Actual File | Status | Notes |
|------------------|-------------|:------:|-------|
| `config/routes.rb` - search collection 3개 | clients:79, suppliers:85, projects:92 | PASS | 3개 collection route 존재 |
| `app/controllers/clients_controller.rb` - search | search action line 100-106 | PASS | |
| `app/controllers/suppliers_controller.rb` - search | search action line 90-96 | PASS | |
| `app/controllers/projects_controller.rb` - search | search action line 62-68 | PASS | |
| `app/javascript/controllers/autocomplete_controller.js` - 신규 | 203 lines, 완전한 구현 | PASS | |
| `app/views/orders/_form.html.erb` - 3개 select -> 위젯 교체 | 3개 autocomplete 위젯 구현 | PASS | |

**File List Summary**: 6개 항목 전체 PASS = **100%**

---

## 3. Added Features (Design X, Implementation O)

| # | Item | Implementation Location | Description |
|:-:|------|------------------------|-------------|
| 1 | `_fetchInitialById(id)` | autocomplete_controller.js:112-122 | 초기값 로딩 시 q="" 결과에 항목이 없으면 `?id=` 파라미터로 재조회하는 fallback |
| 2 | `_itemHover(e)` | autocomplete_controller.js:159-163 | 마우스 hover 시 하이라이트 연동 |
| 3 | `_esc(str)` | autocomplete_controller.js:196-202 | HTML 이스케이프 유틸리티 (XSS 방지) |
| 4 | `_renderEmpty()` | autocomplete_controller.js:147-151 | 결과 없음 UI ("결과가 없습니다") |
| 5 | `disconnect()` | autocomplete_controller.js:33-36 | 이벤트 리스너 정리 + timer clear (메모리 누수 방지) |
| 6 | 편집 폼 기존값 표시 | _form.html.erb:26-28 등 | `order.client_id.present?` 에 따라 badge/input 초기 visibility 제어 |
| 7 | Dark mode 지원 | _form.html.erb, autocomplete_controller.js | `dark:bg-gray-800`, `dark:text-white` 등 |
| 8 | sublabel fallback chain | autocomplete_controller.js:132 | `item[sublabelValue] || item.country || item.industry || item.client_name` |

> Note: 위 항목들은 Design에 명시되지 않았지만 프로덕션 품질에 필요한 **합리적 추가 구현**입니다. 특히 XSS 방지(`_esc`), 메모리 누수 방지(`disconnect`), 편집 폼 지원은 필수 요소입니다.

---

## 4. Match Rate Summary

```
+-----------------------------------------------+
|  Overall Match Rate: 95%                       |
+-----------------------------------------------+
|                                                |
|  API Endpoints:         9/10 = 90%             |
|    PASS:  9 items                              |
|    CHANGED: 1 item (supplier response source)  |
|                                                |
|  Stimulus Controller:   20/22 = 91%            |
|    PASS:  20 items                             |
|    CHANGED: 2 items (value name, targets)      |
|                                                |
|  ERB Widget Pattern:    10/10 = 100%           |
|    PASS:  10 items                             |
|                                                |
|  File List:             6/6  = 100%            |
|    PASS:  6 items                              |
|                                                |
|  Added (not in design): 8 items                |
|  Missing (not impl'd):  0 items               |
|                                                |
+-----------------------------------------------+
|  Weighted Overall:                             |
|    (90 + 91 + 100 + 100) / 4 = 95.25%         |
+-----------------------------------------------+
```

---

## 5. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| API Endpoints Match | 90% | PASS |
| Stimulus Controller Match | 91% | PASS |
| ERB Widget Match | 100% | PASS |
| File List Match | 100% | PASS |
| **Overall Design Match** | **95%** | **PASS** |

---

## 6. Changed Items (Design != Implementation)

| # | Item | Design | Implementation | Impact | Verdict |
|:-:|------|--------|----------------|--------|---------|
| 1 | Supplier `code` source | `code` (model field) | `ecount_code` (mapped to key `code`) | Low | Intentional -- Supplier has no `code` field |
| 2 | Supplier `industry` value | raw enum value | `industry_label` (human-readable) | Low | Improvement -- UX-friendly display |
| 3 | Value: `labelField` | `labelField(String="name")` | `sublabel(String="code")` | Low | Simplification -- main label always `name` |
| 4 | Targets: `container` | `container` target exists | Not present (uses `element`) | Low | Stimulus best practice |
| 5 | Targets: badge sub-targets | single `badge` target | `badge` + `badgeLabel` + `badgeSub` | Low | Improvement -- avoids innerHTML for XSS safety |

---

## 7. Recommended Actions

### 7.1 Design Document Updates (Optional)

아래 항목들은 Design 문서를 현재 구현에 맞게 업데이트하면 좋으나, **기능적 영향이 없어 필수는 아닙니다**:

| Priority | Item | Description |
|:--------:|------|-------------|
| Low | Supplier response 명세 | `code` -> `ecount_code` 매핑, `industry` -> `industry_label` 반영 |
| Low | Values 명세 | `labelField` -> `sublabel` 반영, default 값 포함 |
| Low | Targets 명세 | `container` 제거, `badgeLabel`/`badgeSub` 추가 |
| Low | 추가 구현 항목 | `_fetchInitialById`, `_esc`, `disconnect`, dark mode 등 기술 |

### 7.2 Synchronization Verdict

Match Rate **95%** >= 90% threshold --> **PASS**

모든 변경 항목은 Impact: Low이며, Design 의도를 충실히 구현하면서 프로덕션 품질을 위한 합리적 개선입니다. 별도의 코드 수정이나 즉각적인 Action은 필요하지 않습니다.

---

## 8. Gap Categories Breakdown

| Category | Count | Items |
|----------|:-----:|-------|
| Missing Features (Design O, Impl X) | 0 | -- |
| Added Features (Design X, Impl O) | 8 | fetchInitialById, itemHover, esc, renderEmpty, disconnect, edit form, dark mode, sublabel fallback |
| Changed Features (Design != Impl) | 5 | supplier code/industry source, labelField->sublabel, targets restructure |
| Matched Features | 45 | API routes, search actions, controller logic, ERB widgets, keyboard nav, etc. |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial gap analysis | bkit-gap-detector |
