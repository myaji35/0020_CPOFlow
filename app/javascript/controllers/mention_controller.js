import { Controller } from "@hotwired/stimulus"

// @사용자 멘션 드롭다운 컨트롤러
// data-controller="mention"
// data-mention-mode-value="comment" | "task"
// data-mention-url-value="/users/mention_suggestions"
export default class extends Controller {
  static values  = { mode: String, url: String }
  static targets = ["input", "dropdown", "employeeId"]

  connect() {
    this._query      = ""
    this._atIndex    = -1
    this._activeIdx  = -1
    this._open       = false
    this._items      = []
    this._bound      = {
      keydown:   this._onKeydown.bind(this),
      clickOut:  this._onClickOut.bind(this)
    }
    this.inputTarget.addEventListener("keydown", this._bound.keydown)
    document.addEventListener("click", this._bound.clickOut)
  }

  disconnect() {
    this.inputTarget.removeEventListener("keydown", this._bound.keydown)
    document.removeEventListener("click", this._bound.clickOut)
    this._closeDropdown()
  }

  // 입력 이벤트 (data-action="input->mention#onInput")
  onInput(event) {
    const input = event.target
    const val   = input.value
    const pos   = input.selectionStart

    // 커서 앞 텍스트에서 @ 탐색
    const before = val.slice(0, pos)
    const match  = before.match(/(?:^|[\s\n])@([\w가-힣]*)$/)

    if (match) {
      this._atIndex = before.lastIndexOf("@")
      this._query   = match[1]
      this._fetchSuggestions(this._query)
    } else {
      this._closeDropdown()
    }
  }

  _onKeydown(event) {
    if (!this._open) return
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._moveActive(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this._moveActive(-1)
        break
      case "Enter":
        if (this._activeIdx >= 0) {
          event.preventDefault()
          this._selectItem(this._items[this._activeIdx])
        }
        break
      case "Escape":
        this._closeDropdown()
        break
    }
  }

  _onClickOut(event) {
    if (!this.dropdownTarget.contains(event.target) && event.target !== this.inputTarget) {
      this._closeDropdown()
    }
  }

  async _fetchSuggestions(q) {
    const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
    try {
      const res   = await fetch(url, { headers: { "Accept": "application/json", "X-CSRF-Token": this._csrfToken() } })
      const items = await res.json()
      this._items = items
      this._renderDropdown(items)
    } catch (_) {
      this._closeDropdown()
    }
  }

  _renderDropdown(items) {
    if (!items.length) { this._closeDropdown(); return }

    const rect = this.inputTarget.getBoundingClientRect()
    const dd   = this.dropdownTarget

    dd.innerHTML = items.map((item, idx) => `
      <div class="mention-item flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 text-sm"
           data-idx="${idx}" data-mention-target="item">
        <span class="w-6 h-6 rounded-full bg-primary text-white text-xs flex items-center justify-center font-bold shrink-0">
          ${item.initials}
        </span>
        <span class="flex-1 text-gray-800 dark:text-gray-200">${item.display_name}</span>
        ${item.branch ? `<span class="text-xs text-gray-400">${item.branch}</span>` : ""}
      </div>
    `).join("")

    // 클릭 이벤트
    dd.querySelectorAll(".mention-item").forEach(el => {
      el.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._selectItem(items[parseInt(el.dataset.idx)])
      })
      el.addEventListener("mouseover", () => {
        this._activeIdx = parseInt(el.dataset.idx)
        this._highlightActive()
      })
    })

    // 위치 지정 (fixed — 드로어 z-index 위)
    dd.style.cssText = `
      position: fixed;
      top: ${rect.bottom + 4}px;
      left: ${rect.left}px;
      width: ${Math.max(rect.width, 220)}px;
      z-index: 9999;
      display: block;
    `
    this._open      = true
    this._activeIdx = 0
    this._highlightActive()
  }

  _selectItem(item) {
    if (!item) return
    const input  = this.inputTarget
    const val    = input.value
    const before = val.slice(0, this._atIndex)
    const after  = val.slice(input.selectionStart)

    input.value = `${before}@${item.display_name} ${after}`
    input.setSelectionRange(
      before.length + item.display_name.length + 2,
      before.length + item.display_name.length + 2
    )

    // task 모드: hidden input에 user_id 설정 (Task.assignee_id는 User FK)
    if (this.modeValue === "task" && this.hasEmployeeIdTarget) {
      this.employeeIdTarget.value = item.id
    }

    this._closeDropdown()
    input.focus()
  }

  _moveActive(dir) {
    this._activeIdx = Math.max(0, Math.min(this._items.length - 1, this._activeIdx + dir))
    this._highlightActive()
  }

  _highlightActive() {
    this.dropdownTarget.querySelectorAll(".mention-item").forEach((el, idx) => {
      el.classList.toggle("bg-gray-100", idx === this._activeIdx)
      el.classList.toggle("dark:bg-gray-700", idx === this._activeIdx)
    })
  }

  _closeDropdown() {
    this.dropdownTarget.style.display = "none"
    this.dropdownTarget.innerHTML     = ""
    this._open     = false
    this._activeIdx = -1
    this._items    = []
  }

  _csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
