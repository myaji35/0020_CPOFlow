import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!window.Sortable) {
      // CDN 로드 (이미 있으면 스킵)
      const script = document.createElement("script")
      script.src = "https://cdn.jsdelivr.net/npm/sortablejs@1.15.0/Sortable.min.js"
      script.onload = () => this.initSortable()
      document.head.appendChild(script)
    } else {
      this.initSortable()
    }
  }

  initSortable() {
    Sortable.create(this.element, {
      handle: "[data-sortable-handle]",
      animation: 150,
      onEnd: () => this.persist()
    })
  }

  async persist() {
    const ids = Array.from(this.element.querySelectorAll("[data-cs-id]"))
                    .map(el => parseInt(el.dataset.csId, 10))
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ order: ids })
    })
  }
}
