import { Controller } from "@hotwired/stimulus"

// @사용자 멘션 드롭다운 컨트롤러
// data-controller="mention"
// data-mention-mode-value="comment" | "task"
// data-mention-url-value="/users/mention_suggestions"
export default class extends Controller {
  static values  = { mode: String, url: String }
  static targets = ["input", "dropdown", "employeeId"]

  connect() {
    console.log("[mention] controller connected", this.element)
    this._query      = ""
    this._atIndex    = -1
    this._activeIdx  = -1
    this._open       = false
    this._items      = []
    this._bound      = {
      keydown:   this._onKeydown.bind(this),
      clickOut:  this._onClickOut.bind(this),
      keyup:     this._onKeyup.bind(this),
      input:     this._onInputEvent.bind(this)
    }
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("keydown", this._bound.keydown)
      this.inputTarget.addEventListener("keyup", this._bound.keyup)
      this.inputTarget.addEventListener("input", this._bound.input)  // 안전장치: data-action 없이도 동작
    } else {
      console.warn("[mention] inputTarget not found — data-mention-target=\"input\" 확인 필요")
    }
    document.addEventListener("click", this._bound.clickOut)
  }

  disconnect() {
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("keydown", this._bound.keydown)
      this.inputTarget.removeEventListener("keyup", this._bound.keyup)
      this.inputTarget.removeEventListener("input", this._bound.input)
    }
    document.removeEventListener("click", this._bound.clickOut)
    this._closeDropdown()
  }

  _onInputEvent(event) {
    this._detectAtMention(event.target)
  }

  // 입력 이벤트 (data-action="input->mention#onInput")
  onInput(event) {
    this._detectAtMention(event.target)
  }

  // 화살표/엔터/선택 이후 커서 이동 감지용
  _onKeyup(event) {
    if (["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) return
    this._detectAtMention(event.target)
  }

  _detectAtMention(input) {
    const val = input.value
    const pos = input.selectionStart
    const before = val.slice(0, pos)
    // 커서 앞에서 가장 가까운 @를 찾되, 문자열 시작 또는 공백 직후의 @만 유효
    // 디버그: 값/위치/매칭 여부 로그
    const match = before.match(/(?:^|\s)@([\w가-힣]*)$/)
    console.log("[mention] detect", { val: JSON.stringify(val), pos, hasAt: before.includes("@"), match: match?.[1] })

    if (match) {
      this._atIndex = before.lastIndexOf("@")
      this._query   = match[1]
      console.log("[mention] -> fetch", this._query)
      this._fetchSuggestions(this._query)
    } else if (before.includes("@")) {
      // fallback: @ 뒤 단어 추출 (보이지 않는 문자나 특이 패턴 대응)
      const lastAt = before.lastIndexOf("@")
      const afterAt = before.slice(lastAt + 1)
      // @ 뒤에 공백/개행이 없으면 멘션 후보로 간주
      if (!/\s/.test(afterAt)) {
        this._atIndex = lastAt
        this._query = afterAt.replace(/[^\w가-힣]/g, "")
        console.log("[mention] fallback fetch", this._query)
        this._fetchSuggestions(this._query)
        return
      }
      this._closeDropdown()
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
      const res = await fetch(url, {
        headers: { "Accept": "application/json", "X-CSRF-Token": this._csrfToken() },
        credentials: "same-origin",
        redirect: "manual"
      })
      // 세션 만료 등으로 redirect / 비-JSON 응답 처리
      if (!res.ok || res.type === "opaqueredirect" || !(res.headers.get("content-type") || "").includes("json")) {
        this._items = []
        this._renderError("직원 목록을 불러올 수 없습니다 (재로그인 필요)")
        return
      }
      const items = await res.json()
      this._items = Array.isArray(items) ? items : []
      this._renderDropdown(this._items)
    } catch (err) {
      console.error("[mention] fetch error", err)
      this._items = []
      this._renderError("멘션 목록 로딩 실패")
    }
  }

  _renderError(msg) {
    const rect = this.inputTarget.getBoundingClientRect()
    const dd   = this.dropdownTarget
    dd.innerHTML = `<div class="px-3 py-2 text-sm text-red-500">${this._escape(msg)}</div>`
    dd.style.cssText = `position:fixed; top:${rect.bottom + 4}px; left:${rect.left}px; width:${Math.max(rect.width, 220)}px; z-index:9999; display:block;`
    this._open = true
  }

  _renderDropdown(items) {
    const rect = this.inputTarget.getBoundingClientRect()
    const dd   = this.dropdownTarget

    if (!items.length) {
      dd.innerHTML = `
        <div class="px-3 py-2 text-sm text-gray-500 dark:text-gray-400">
          검색 결과가 없습니다
        </div>
      `
    } else {
      dd.innerHTML = items.map((item, idx) => `
        <div class="mention-item flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 text-sm"
             data-idx="${idx}" data-mention-target="item">
          <span class="w-6 h-6 rounded-full bg-primary text-white text-xs flex items-center justify-center font-bold shrink-0">
            ${this._escape(item.initials)}
          </span>
          <span class="flex-1 text-gray-800 dark:text-gray-200">${this._escape(item.display_name)}</span>
          ${item.job_title ? `<span class="text-xs text-gray-400">${this._escape(item.job_title)}</span>` : (item.branch ? `<span class="text-xs text-gray-400">${this._escape(item.branch)}</span>` : "")}
        </div>
      `).join("")
    }

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

    // task/assign 모드: hidden input에 user_id 또는 employee_id 설정
    if ((this.modeValue === "task" || this.modeValue === "assign") && this.hasEmployeeIdTarget) {
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

  _escape(str) {
    return String(str ?? "").replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
    }[c]))
  }
}
