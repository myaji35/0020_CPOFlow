# Design: order-form-autocomplete

## API Endpoints

### GET /clients/search
- Params: `q` (string, min 1 char)
- Response: `[{ id, name, code, country }]` (max 10)
- Auth: require_login

### GET /suppliers/search
- Params: `q`
- Response: `[{ id, name, code, industry }]` (max 10)

### GET /projects/search
- Params: `q`
- Response: `[{ id, name, client_name, status }]` (max 10)

## Stimulus Controller: autocomplete_controller.js

```
Values: url(String), placeholder(String), labelField(String="name")
Targets: input, hidden, dropdown, badge, container

connect():
  - hiddenValue 있으면 → fetchInitial(id) → badge 표시
  - input에 debounce 이벤트 등록

onInput(e):
  - q.length < 1 → closeDropdown()
  - debounce 300ms → fetchResults(q)

fetchResults(q):
  - fetch(`${url}?q=${q}`)
  - renderDropdown(results)

selectItem(id, label, sublabel):
  - hiddenTarget.value = id
  - badgeTarget: 표시 (label + sublabel + X버튼)
  - inputTarget: 숨김
  - dropdownTarget: 닫기

clearSelection():
  - hiddenTarget.value = ""
  - badgeTarget: 숨김
  - inputTarget: 재노출, focus

키보드: ↑↓ → 포커스 이동, Enter → 선택, Escape → 닫기
외부클릭: dropdown 닫기
```

## ERB 위젯 패턴

```erb
<div data-controller="autocomplete"
     data-autocomplete-url-value="/clients/search"
     data-autocomplete-placeholder-value="발주처 검색...">
  <input type="hidden" name="order[client_id]" value="<%= order.client_id %>"
         data-autocomplete-target="hidden">
  <!-- badge, input, dropdown targets -->
</div>
```

## 파일 목록

| 파일 | 변경 |
|------|------|
| `config/routes.rb` | search collection 라우트 3개 |
| `app/controllers/clients_controller.rb` | search 액션 |
| `app/controllers/suppliers_controller.rb` | search 액션 |
| `app/controllers/projects_controller.rb` | search 액션 |
| `app/javascript/controllers/autocomplete_controller.js` | 신규 |
| `app/views/orders/_form.html.erb` | 3개 select → 위젯 교체 |
