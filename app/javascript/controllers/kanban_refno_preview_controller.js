import { Controller } from "@hotwired/stimulus"

// Procurement Ontology M3 — 칸반 reference_no 호버 미니프리뷰
//
// Usage:
//   <span data-controller="kanban-refno-preview"
//         data-kanban-refno-preview-ref-value="ENEC-2026-0042">...</span>
//
// 동작:
//   mouseenter → 300ms timer → fetch /orders/preview_by_ref?ref=...
//   mouseleave → 타이머 취소 + 툴팁 제거
export default class extends Controller {
  static values = { ref: String }

  connect() {
    this.boundEnter = this.enter.bind(this)
    this.boundLeave = this.leave.bind(this)
    this.element.addEventListener("mouseenter", this.boundEnter)
    this.element.addEventListener("mouseleave", this.boundLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.boundEnter)
    this.element.removeEventListener("mouseleave", this.boundLeave)
    this.removeTooltip()
  }

  enter() {
    if (!this.refValue) return
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.show(), 300)
  }

  leave() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
    this.removeTooltip()
  }

  async show() {
    try {
      const r = await fetch(`/orders/preview_by_ref?ref=${encodeURIComponent(this.refValue)}`, {
        headers: { "Accept": "text/html" }
      })
      if (!r.ok) return
      const html = await r.text()
      this.tip = document.createElement("div")
      this.tip.style.position = "absolute"
      this.tip.style.zIndex = "9999"
      this.tip.style.pointerEvents = "auto"
      this.tip.innerHTML = html
      document.body.appendChild(this.tip)
      const rect = this.element.getBoundingClientRect()
      this.tip.style.top  = (window.scrollY + rect.bottom + 4) + "px"
      this.tip.style.left = (window.scrollX + rect.left) + "px"
    } catch (_) {
      // 네트워크 실패 — 조용히 무시
    }
  }

  removeTooltip() {
    if (this.tip) {
      this.tip.remove()
      this.tip = null
    }
  }
}
