import { Controller } from "@hotwired/stimulus"

// @사용자 멘션 드롭다운 컨트롤러 (v3)
//
// 구조적 특성:
// - dropdownTarget은 원래 DOM 위치에서 "proxy" 역할만 함 (Stimulus가 target 검색 실패 방지)
// - 실제 렌더링은 별도 document.body 직속 <div>(this._panel)에 수행 → viewport fixed,
//   drawer 의 transform/overflow 영향 없음
// - input 이벤트는 connect에서 단일 바인딩. data-action 불필요.
//
// data-controller="mention"
// data-mention-mode-value="comment" | "task" | "assign"
// data-mention-url-value="/users/mention_suggestions"
//
// Targets:
//   input      : <input/textarea>
//   dropdown   : 원래 위치 proxy 요소 (실제 표시 X, Stimulus target 유실 방지용)
//   employeeId : (task/assign 모드) 선택된 user_id hidden input
export default class extends Controller {
  static values  = { mode: String, url: String }
  static targets = ["input", "dropdown", "employeeId"]

  connect() {
    this._query      = ""
    this._atIndex    = -1
    this._activeIdx  = -1
    this._open       = false
    this._items      = []
    this._abortCtrl  = null
    this._debounceTimer = null

    // ── body 직속 panel 생성 (실제 렌더링 대상) ────────────
    this._panel = document.createElement("div")
    this._panel.className = "cpoflow-mention-panel"
    this._panel.style.display = "none"
    document.body.appendChild(this._panel)

    // ── 단일 이벤트 바인딩 ────────────
    this._onInput    = this._onInputEvent.bind(this)
    this._onKeydown  = this._onKeydownEvent.bind(this)
    this._onClickOut = this._onClickOutEvent.bind(this)
    this._onScroll   = this._reposition.bind(this)
    this._onResize   = this._reposition.bind(this)

    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("input",   this._onInput)
      this.inputTarget.addEventListener("keydown", this._onKeydown)
    } else {
      console.warn("[mention] inputTarget 없음 — data-mention-target=\"input\" 확인")
    }
    document.addEventListener("click", this._onClickOut, true)
    window.addEventListener("scroll", this._onScroll, true)
    window.addEventListener("resize", this._onResize)
  }

  disconnect() {
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("input",   this._onInput)
      this.inputTarget.removeEventListener("keydown", this._onKeydown)
    }
    document.removeEventListener("click", this._onClickOut, true)
    window.removeEventListener("scroll", this._onScroll, true)
    window.removeEventListener("resize", this._onResize)
    this._cancelPending()
    if (this._panel && this._panel.parentElement === document.body) {
      this._panel.remove()
    }
    this._panel = null
  }

  // data-action="input->mention#onInput" 유지 시에도 호출되지만 _onInput과 동일 경로 → no-op
  onInput(_event) { /* 단일 바인딩으로 대체됨 */ }

  _onInputEvent(event) {
    this._detectAtMention(event.target)
  }

  _onKeydownEvent(event) {
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
        if (this._activeIdx >= 0 && this._items[this._activeIdx]) {
          event.preventDefault()
          this._selectItem(this._items[this._activeIdx])
        }
        break
      case "Escape":
        event.preventDefault()
        this._close()
        break
    }
  }

  _onClickOutEvent(event) {
    if (!this._open) return
    if (event.target === this.inputTarget) return
    if (this._panel && this._panel.contains(event.target)) return
    this._close()
  }

  _detectAtMention(input) {
    const val    = input.value
    const pos    = input.selectionStart
    const before = val.slice(0, pos)
    // 문자열 시작 또는 공백 직후의 @(선택적 단어)까지 매칭
    const match  = before.match(/(?:^|\s)@([\w가-힣]*)$/)

    if (match) {
      this._atIndex = before.lastIndexOf("@")
      this._query   = match[1]
      this._fetch(this._query)
    } else {
      this._close()
    }
  }

  _cancelPending() {
    if (this._abortCtrl) { this._abortCtrl.abort(); this._abortCtrl = null }
    clearTimeout(this._debounceTimer); this._debounceTimer = null
  }

  _fetch(q) {
    this._cancelPending()
    this._abortCtrl = new AbortController()
    const signal = this._abortCtrl.signal
    this._debounceTimer = setTimeout(() => this._doFetch(q, signal), 120)
  }

  async _doFetch(q, signal) {
    const url = `${this.urlValue}?q=${encodeURIComponent(q)}`
    try {
      const res = await fetch(url, {
        headers: { "Accept": "application/json", "X-CSRF-Token": this._csrfToken() },
        credentials: "same-origin",
        redirect: "manual",
        signal
      })
      if (!res.ok || res.type === "opaqueredirect" || !(res.headers.get("content-type") || "").includes("json")) {
        this._renderError("멘션 목록을 불러올 수 없습니다 (재로그인 필요)")
        return
      }
      const items = await res.json()
      // stale 응답 차단 — 현재 쿼리와 다르면 폐기
      if (q !== this._query) return

      const qLower = (q || "").toLowerCase().trim()
      let list = Array.isArray(items) ? items : []
      if (qLower.length > 0) {
        list = list.filter(it => (it.display_name || "").toLowerCase().includes(qLower))
      }
      this._items = list
      this._render(list)
    } catch (err) {
      if (err.name === "AbortError") return
      console.error("[mention] fetch error", err)
      this._renderError("멘션 목록 로딩 실패")
    }
  }

  _render(items) {
    if (!this._panel) return
    if (!items.length) {
      this._panel.innerHTML = `<div style="padding:8px 12px; font-size:13px; color:#6b7585;">검색 결과가 없습니다</div>`
    } else {
      this._panel.innerHTML = items.map((item, idx) => `
        <div class="cpoflow-mention-item" data-idx="${idx}"
             style="display:flex; align-items:center; gap:8px; padding:8px 12px; cursor:pointer; font-size:13px;">
          <span style="width:22px; height:22px; border-radius:50%; background:#166c72; color:white;
                       display:grid; place-items:center; font-size:10px; font-weight:700; flex-shrink:0;">
            ${this._escape(item.initials)}
          </span>
          <span style="flex:1; color:#151a21; font-weight:500; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
            ${this._escape(item.display_name)}
          </span>
          ${item.job_title
            ? `<span style="font-size:11px; color:#97a0ad; flex-shrink:0;">${this._escape(item.job_title)}</span>`
            : (item.branch ? `<span style="font-size:11px; color:#97a0ad; flex-shrink:0;">${this._escape(item.branch)}</span>` : "")}
        </div>
      `).join("")

      // 이벤트 바인딩
      this._panel.querySelectorAll(".cpoflow-mention-item").forEach(el => {
        el.addEventListener("mousedown", (e) => {
          e.preventDefault()
          e.stopPropagation()
          const idx = parseInt(el.dataset.idx, 10)
          this._selectItem(items[idx])
        })
        el.addEventListener("mouseenter", () => {
          this._activeIdx = parseInt(el.dataset.idx, 10)
          this._highlightActive()
        })
      })
    }
    this._showPanel()
    this._activeIdx = items.length ? 0 : -1
    this._highlightActive()
  }

  _renderError(msg) {
    if (!this._panel) return
    this._panel.innerHTML = `<div style="padding:8px 12px; font-size:13px; color:#c84431;">${this._escape(msg)}</div>`
    this._showPanel()
  }

  _showPanel() {
    if (!this._panel || !this.hasInputTarget) return
    const rect  = this.inputTarget.getBoundingClientRect()
    const width = Math.max(rect.width, 260)
    let   left  = rect.left
    if (left + width > window.innerWidth - 8) {
      left = Math.max(8, window.innerWidth - width - 8)
    }
    const top = rect.bottom + 4
    Object.assign(this._panel.style, {
      position:   "fixed",
      top:        `${top}px`,
      left:       `${left}px`,
      width:      `${width}px`,
      maxHeight:  "320px",
      overflowY:  "auto",
      background: "white",
      border:     "1px solid #e7eaee",
      borderRadius: "8px",
      boxShadow:  "0 10px 25px -5px rgba(12,16,20,0.15), 0 4px 6px -2px rgba(12,16,20,0.08)",
      zIndex:     "2147483647",
      display:    "block"
    })
    this._open = true
  }

  _reposition() {
    if (this._open) this._showPanel()
  }

  _moveActive(dir) {
    if (!this._items.length) return
    this._activeIdx = (this._activeIdx + dir + this._items.length) % this._items.length
    this._highlightActive()
  }

  _highlightActive() {
    if (!this._panel) return
    this._panel.querySelectorAll(".cpoflow-mention-item").forEach((el, idx) => {
      if (idx === this._activeIdx) {
        el.style.background = "#f5f6f8"
      } else {
        el.style.background = ""
      }
    })
    // scroll into view
    const active = this._panel.querySelector(`.cpoflow-mention-item[data-idx="${this._activeIdx}"]`)
    if (active && active.scrollIntoView) {
      active.scrollIntoView({ block: "nearest" })
    }
  }

  _selectItem(item) {
    if (!item || !this.hasInputTarget) return
    const input  = this.inputTarget
    const val    = input.value
    const before = val.slice(0, this._atIndex)
    const after  = val.slice(input.selectionStart)
    const mention = `@${item.display_name} `

    input.value = before + mention + after
    const cursor = (before + mention).length
    input.setSelectionRange(cursor, cursor)

    if ((this.modeValue === "task" || this.modeValue === "assign") && this.hasEmployeeIdTarget) {
      this.employeeIdTarget.value = item.id
    }

    this._atIndex = -1
    this._query   = ""
    this._close()
    queueMicrotask(() => input.focus())
  }

  _close() {
    this._cancelPending()
    if (this._panel) {
      this._panel.style.display = "none"
      this._panel.innerHTML     = ""
    }
    this._open      = false
    this._activeIdx = -1
    this._items     = []
  }

  // 하위 호환 — 기존 _closeDropdown 호출 대응 (현재 내부에서만 사용)
  _closeDropdown() { this._close() }

  _csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  _escape(str) {
    return String(str ?? "").replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
    }[c]))
  }
}
