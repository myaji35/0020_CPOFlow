import { Controller } from "@hotwired/stimulus"

// Command Palette — Cmd+K / Ctrl+K 트리거 전체 검색
export default class extends Controller {
  static targets = ["modal", "input", "results", "item"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
    this.selectedIndex = -1
    this.debounceTimer = null
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(e) {
    // Cmd+K (Mac) or Ctrl+K (Win/Linux)
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault()
      this.open()
      return
    }
    if (!this.isOpen) return

    if (e.key === "Escape") { this.close(); return }
    if (e.key === "ArrowDown") { e.preventDefault(); this.moveDown(); return }
    if (e.key === "ArrowUp")   { e.preventDefault(); this.moveUp();   return }
    if (e.key === "Enter")     { e.preventDefault(); this.selectCurrent(); return }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.inputTarget.focus()
    this.resultsTarget.innerHTML = this.emptyHint()
    this.isOpen = true
    this.selectedIndex = -1
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
      this.resultsTarget.innerHTML = this.emptyHint()
      return
    }
    this.debounceTimer = setTimeout(() => this.fetchResults(q), 280)
  }

  async fetchResults(q) {
    this.resultsTarget.innerHTML = `<div class="px-4 py-3 text-sm text-gray-400">검색 중...</div>`
    try {
      const res = await fetch(`/search?q=${encodeURIComponent(q)}`, {
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
      this.resultsTarget.innerHTML = `<div class="px-4 py-6 text-center text-sm text-gray-400">"${q}" 검색 결과 없음</div>`
      return
    }
    const typeLabel = { order: "주문", client: "발주처", supplier: "거래처", employee: "직원", project: "현장" }
    const typeColor = {
      order: "bg-blue-50 text-blue-600 dark:bg-blue-900/30 dark:text-blue-400",
      client: "bg-purple-50 text-purple-600 dark:bg-purple-900/30 dark:text-purple-400",
      supplier: "bg-yellow-50 text-yellow-600 dark:bg-yellow-900/30 dark:text-yellow-400",
      employee: "bg-green-50 text-green-600 dark:bg-green-900/30 dark:text-green-400",
      project: "bg-orange-50 text-orange-600 dark:bg-orange-900/30 dark:text-orange-400"
    }
    this.resultsTarget.innerHTML = items.map((item, i) => `
      <a href="${item.url}"
         data-result-item
         class="flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors result-item"
         data-index="${i}">
        <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium min-w-[40px] justify-center ${typeColor[item.type] || ''}">
          ${typeLabel[item.type] || item.type}
        </span>
        <span class="flex-1 min-w-0">
          <span class="block text-sm text-gray-900 dark:text-white truncate">${item.label}</span>
          ${item.sub ? `<span class="block text-xs text-gray-400 dark:text-gray-500 truncate">${item.sub}</span>` : ""}
        </span>
        <svg class="w-4 h-4 text-gray-300 group-hover:text-gray-500 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 18 15 12 9 6"/></svg>
      </a>
    `).join("")
    this.selectedIndex = -1
  }

  moveDown() {
    const items = this.resultsTarget.querySelectorAll(".result-item")
    if (!items.length) return
    this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
    this.highlightItem(items)
  }

  moveUp() {
    const items = this.resultsTarget.querySelectorAll(".result-item")
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
    const items = this.resultsTarget.querySelectorAll(".result-item")
    if (this.selectedIndex >= 0 && items[this.selectedIndex]) {
      window.location.href = items[this.selectedIndex].href
    }
  }

  emptyHint() {
    return `<div class="px-4 py-6 text-center">
      <p class="text-sm text-gray-400 dark:text-gray-500">검색어를 2자 이상 입력하세요</p>
      <p class="text-xs text-gray-300 dark:text-gray-600 mt-1">주문 · 발주처 · 거래처 · 직원 · 현장 통합 검색</p>
    </div>`
  }
}
