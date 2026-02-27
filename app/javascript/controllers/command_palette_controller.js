import { Controller } from "@hotwired/stimulus"

// Command Palette — Cmd+K / Ctrl+K 트리거 전체 검색
export default class extends Controller {
  static targets = ["modal", "input", "results", "item"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleOpen    = () => this.open()
    document.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("open-command-palette", this.handleOpen)
    this.selectedIndex = -1
    this.debounceTimer = null

    // 결과 클릭 이벤트 위임
    this.resultsTarget.addEventListener("click", (e) => {
      const item = e.target.closest(".result-item:not(.recent-item)")
      if (item) this.activateItem(item)
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("open-command-palette", this.handleOpen)
  }

  handleKeydown(e) {
    // Cmd+K (Mac) or Ctrl+K (Win/Linux)
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault()
      this.open()
      return
    }
    if (!this.isOpen) return

    if (e.key === "Escape")    { this.close();          return }
    if (e.key === "ArrowDown") { e.preventDefault(); this.moveDown(); return }
    if (e.key === "ArrowUp")   { e.preventDefault(); this.moveUp();   return }
    if (e.key === "Enter")     { e.preventDefault(); this.selectCurrent(); return }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.inputTarget.focus()
    this.isOpen = true
    this.selectedIndex = -1
    this.showRecentSearches()
  }

  close() {
    this.modalTarget.classList.add("hidden")
    this.isOpen = false
  }

  closeOnBackdrop(e) {
    if (e.target === this.modalTarget) this.close()
  }

  search() {
    clearTimeout(this.debounceTimer)
    const q = this.inputTarget.value.trim()
    if (q.length < 2) {
      this.showRecentSearches()
      return
    }
    this.debounceTimer = setTimeout(() => this.fetchResults(q), 280)
  }

  // 최근 검색어 표시
  showRecentSearches() {
    const recent = this.getRecentSearches()
    if (recent.length === 0) {
      this.resultsTarget.innerHTML = this.emptyHint()
      return
    }
    this.resultsTarget.innerHTML = `
      <div class="px-4 pt-3 pb-1">
        <p class="text-xs font-medium text-gray-400 dark:text-gray-500 uppercase tracking-wide">최근 검색</p>
      </div>
      ${recent.map(q => `
        <div data-recent-query="${q.replace(/"/g, "&quot;")}"
             class="flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors result-item recent-item">
          <svg class="w-4 h-4 text-gray-300 dark:text-gray-600 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.5"/>
          </svg>
          <span class="flex-1 text-sm text-gray-600 dark:text-gray-300">${q}</span>
          <svg class="w-3.5 h-3.5 text-gray-200 dark:text-gray-600 group-hover:text-gray-400 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="9 18 15 12 9 6"/>
          </svg>
        </div>
      `).join("")}
    `
    // 최근 검색어 클릭
    this.resultsTarget.querySelectorAll(".recent-item").forEach(el => {
      el.addEventListener("click", () => this.searchFrom(el.dataset.recentQuery))
    })
  }

  // 최근 검색어 클릭 → 해당 검색어로 즉시 검색
  searchFrom(q) {
    this.inputTarget.value = q
    this.fetchResults(q)
  }

  // localStorage 헬퍼
  getRecentSearches() {
    try { return JSON.parse(localStorage.getItem("cpoflow_recent_searches") || "[]") }
    catch { return [] }
  }

  saveRecentSearch(q) {
    const recent  = this.getRecentSearches()
    const updated = [q, ...recent.filter(r => r !== q)].slice(0, 5)
    localStorage.setItem("cpoflow_recent_searches", JSON.stringify(updated))
  }

  async fetchResults(q) {
    this.resultsTarget.innerHTML = `<div class="px-4 py-3 text-sm text-gray-400 dark:text-gray-500">검색 중...</div>`
    try {
      const res  = await fetch(`/search?q=${encodeURIComponent(q)}`, {
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
      })
      const data = await res.json()
      this.renderResults(data, q)
    } catch {
      this.resultsTarget.innerHTML = `<div class="px-4 py-3 text-sm text-red-500">검색 오류</div>`
    }
  }

  renderResults(items, q) {
    if (items.length === 0) {
      this.resultsTarget.innerHTML = `<div class="px-4 py-6 text-center text-sm text-gray-400 dark:text-gray-500">"${q}" 검색 결과 없음</div>`
      return
    }

    const typeLabel = { order: "주문", client: "발주처", supplier: "거래처", employee: "직원", project: "현장" }
    const typeColor = {
      order:    "bg-blue-50 text-blue-600 dark:bg-blue-900/30 dark:text-blue-400",
      client:   "bg-purple-50 text-purple-600 dark:bg-purple-900/30 dark:text-purple-400",
      supplier: "bg-yellow-50 text-yellow-600 dark:bg-yellow-900/30 dark:text-yellow-400",
      employee: "bg-green-50 text-green-600 dark:bg-green-900/30 dark:text-green-400",
      project:  "bg-orange-50 text-orange-600 dark:bg-orange-900/30 dark:text-orange-400"
    }

    this.resultsTarget.innerHTML = items.map((item, i) => {
      const label = this.highlight(item.label || "", q)
      const sub   = item.sub ? this.highlight(item.sub, q) : ""
      const badge = `<span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium min-w-[40px] justify-center ${typeColor[item.type] || "bg-gray-100 text-gray-500"}">${typeLabel[item.type] || item.type}</span>`
      const chevron = `<svg class="w-4 h-4 text-gray-300 dark:text-gray-600 group-hover:text-gray-500 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 18 15 12 9 6"/></svg>`
      const content = `
        ${badge}
        <span class="flex-1 min-w-0">
          <span class="block text-sm text-gray-900 dark:text-white truncate">${label}</span>
          ${sub ? `<span class="block text-xs text-gray-400 dark:text-gray-500 truncate">${sub}</span>` : ""}
        </span>
        ${chevron}
      `
      const baseClass = `flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors result-item`

      if (item.type === "order") {
        // Order → openOrderDrawer (페이지 이동 없음)
        return `<div data-result-item
                     data-order-id="${item.id}"
                     data-order-title="${(item.label || "").replace(/"/g, "&quot;")}"
                     data-order-url="${item.url}"
                     class="${baseClass}"
                     data-index="${i}">${content}</div>`
      } else {
        // 기타 → 기존 링크
        return `<a href="${item.url}"
                   data-result-item
                   class="${baseClass}"
                   data-index="${i}">${content}</a>`
      }
    }).join("")

    this.selectedIndex = -1
  }

  // 검색어 하이라이팅
  highlight(text, q) {
    if (!q || !text) return text
    const escaped = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    return String(text).replace(
      new RegExp(`(${escaped})`, "gi"),
      '<mark class="bg-yellow-100 dark:bg-yellow-900/40 text-inherit not-italic rounded px-0.5">$1</mark>'
    )
  }

  // 클릭/Enter 공통 처리
  activateItem(el) {
    const q = this.inputTarget.value.trim()
    if (el.dataset.orderId) {
      // Order → 드로어
      if (q.length >= 2) this.saveRecentSearch(q)
      this.close()
      if (typeof openOrderDrawer === "function") {
        openOrderDrawer(el.dataset.orderId, el.dataset.orderTitle, el.dataset.orderUrl)
      }
    } else if (el.href) {
      // 일반 링크
      if (q.length >= 2) this.saveRecentSearch(q)
      window.location.href = el.href
    }
  }

  moveDown() {
    const items = this.resultsTarget.querySelectorAll(".result-item:not(.recent-item)")
    if (!items.length) return
    this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
    this.highlightItem(items)
  }

  moveUp() {
    const items = this.resultsTarget.querySelectorAll(".result-item:not(.recent-item)")
    if (!items.length) return
    this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
    this.highlightItem(items)
  }

  highlightItem(items) {
    items.forEach((el, i) => {
      if (i === this.selectedIndex) {
        el.classList.add("bg-gray-100", "dark:bg-gray-700/70")
        el.scrollIntoView({ block: "nearest" })
      } else {
        el.classList.remove("bg-gray-100", "dark:bg-gray-700/70")
      }
    })
  }

  selectCurrent() {
    const items = this.resultsTarget.querySelectorAll(".result-item:not(.recent-item)")
    if (this.selectedIndex >= 0 && items[this.selectedIndex]) {
      this.activateItem(items[this.selectedIndex])
    }
  }

  emptyHint() {
    return `<div class="px-4 py-6 text-center">
      <p class="text-sm text-gray-400 dark:text-gray-500">검색어를 2자 이상 입력하세요</p>
      <p class="text-xs text-gray-300 dark:text-gray-600 mt-1">주문 · 발주처 · 거래처 · 직원 · 현장 통합 검색</p>
    </div>`
  }
}
