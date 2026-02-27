import { Controller } from "@hotwired/stimulus"

// 자동완성 위젯 컨트롤러
// data-autocomplete-url-value      : 검색 엔드포인트 (필수)
// data-autocomplete-placeholder-value : input placeholder
// data-autocomplete-sublabel-value : JSON 응답에서 부제목으로 사용할 키 (기본: "code")
export default class extends Controller {
  static values = {
    url: String,
    placeholder: { type: String, default: "검색..." },
    sublabel: { type: String, default: "code" }
  }

  static targets = ["input", "hidden", "dropdown", "badge", "badgeLabel", "badgeSub"]

  connect() {
    this._debounceTimer = null
    this._highlighted = -1

    // 편집 폼: hidden에 이미 값이 있으면 초기 레이블을 가져와 배지 표시
    const existingId = this.hiddenTarget.value
    if (existingId) {
      this._fetchInitial(existingId)
    }

    // 외부 클릭 시 드롭다운 닫기
    this._outsideClick = (e) => {
      if (!this.element.contains(e.target)) this._closeDropdown()
    }
    document.addEventListener("click", this._outsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClick)
    clearTimeout(this._debounceTimer)
  }

  // input 입력 이벤트
  onInput(e) {
    const q = e.target.value.trim()
    clearTimeout(this._debounceTimer)
    if (q.length < 1) {
      this._closeDropdown()
      return
    }
    this._debounceTimer = setTimeout(() => this._fetchResults(q), 300)
  }

  // 키보드 네비게이션
  onKeydown(e) {
    const items = this.dropdownTarget.querySelectorAll("[data-ac-item]")
    if (!items.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this._highlighted = Math.min(this._highlighted + 1, items.length - 1)
      this._highlight(items)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this._highlighted = Math.max(this._highlighted - 1, 0)
      this._highlight(items)
    } else if (e.key === "Enter") {
      e.preventDefault()
      if (this._highlighted >= 0 && items[this._highlighted]) {
        items[this._highlighted].click()
      }
    } else if (e.key === "Escape") {
      this._closeDropdown()
    }
  }

  // 배지 X 버튼 — 선택 해제
  clear() {
    this.hiddenTarget.value = ""
    this.badgeTarget.classList.add("hidden")
    this.inputTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.inputTarget.focus()
    this._closeDropdown()
  }

  // ── private ──────────────────────────────────────────

  _fetchResults(q) {
    fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, {
      headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
    })
      .then(r => r.json())
      .then(data => this._renderDropdown(data))
      .catch(() => this._renderEmpty())
  }

  // 편집 폼 초기값 — ID만 있을 때 레이블 가져오기
  _fetchInitial(id) {
    fetch(`${this.urlValue}?q=`, {
      headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
    })
      .then(r => r.json())
      .then(data => {
        const item = data.find(d => String(d.id) === String(id))
        if (item) {
          this._showBadge(item)
        }
        // 못 찾으면 전체 검색 fallback (항목이 많아 q=""로 안 나온 경우)
        else {
          this._fetchInitialById(id)
        }
      })
      .catch(() => {})
  }

  _fetchInitialById(id) {
    fetch(`${this.urlValue}?id=${encodeURIComponent(id)}`, {
      headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
    })
      .then(r => r.json())
      .then(data => {
        const item = Array.isArray(data) ? data.find(d => String(d.id) === String(id)) : null
        if (item) this._showBadge(item)
      })
      .catch(() => {})
  }

  _renderDropdown(items) {
    this._highlighted = -1
    if (!items.length) {
      this._renderEmpty()
      return
    }

    const html = items.map((item, idx) => {
      const sub = item[this.sublabelValue] || item.country || item.industry || item.client_name || ""
      return `
        <div data-ac-item data-ac-id="${item.id}" data-ac-label="${this._esc(item.name)}" data-ac-sub="${this._esc(sub)}"
             data-action="click->autocomplete#_itemClick mouseenter->autocomplete#_itemHover"
             data-idx="${idx}"
             class="px-3 py-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 flex items-center justify-between gap-2">
          <span class="text-sm text-gray-900 dark:text-white truncate">${this._esc(item.name)}</span>
          ${sub ? `<span class="text-xs text-gray-400 dark:text-gray-500 shrink-0">${this._esc(sub)}</span>` : ""}
        </div>`
    }).join("")

    this.dropdownTarget.innerHTML = html
    this.dropdownTarget.classList.remove("hidden")
  }

  _renderEmpty() {
    this.dropdownTarget.innerHTML = `
      <div class="px-3 py-2 text-sm text-gray-400 dark:text-gray-500">결과가 없습니다</div>`
    this.dropdownTarget.classList.remove("hidden")
  }

  // 아이템 클릭 (data-action 경유)
  _itemClick(e) {
    const el = e.currentTarget
    this._select(el.dataset.acId, el.dataset.acLabel, el.dataset.acSub)
  }

  _itemHover(e) {
    this._highlighted = parseInt(e.currentTarget.dataset.idx, 10)
    const items = this.dropdownTarget.querySelectorAll("[data-ac-item]")
    this._highlight(items)
  }

  _select(id, label, sub) {
    this.hiddenTarget.value = id
    this._showBadge({ id, name: label, [this.sublabelValue]: sub })
    this._closeDropdown()
  }

  _showBadge(item) {
    const sub = item[this.sublabelValue] || item.country || item.industry || item.client_name || ""
    this.badgeLabelTarget.textContent = item.name
    this.badgeSubTarget.textContent = sub ? `(${sub})` : ""
    this.badgeTarget.classList.remove("hidden")
    this.inputTarget.classList.add("hidden")
    this.inputTarget.value = ""
  }

  _closeDropdown() {
    this.dropdownTarget.classList.add("hidden")
    this.dropdownTarget.innerHTML = ""
    this._highlighted = -1
  }

  _highlight(items) {
    items.forEach((el, i) => {
      el.classList.toggle("bg-gray-100", i === this._highlighted)
      el.classList.toggle("dark:bg-gray-700", i === this._highlighted)
    })
    if (items[this._highlighted]) {
      items[this._highlighted].scrollIntoView({ block: "nearest" })
    }
  }

  _esc(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
