import { Controller } from "@hotwired/stimulus"

// 주문 목록 일괄 처리 — 체크박스 선택 및 하단 액션 바 제어
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "actionBar", "count", "form"]

  connect() {
    this.updateState()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => cb.checked = checked)
    this.updateState()
  }

  toggle() {
    const total   = this.checkboxTargets.length
    const checked = this.checkboxTargets.filter(cb => cb.checked).length
    this.selectAllTarget.indeterminate = checked > 0 && checked < total
    this.selectAllTarget.checked = checked === total
    this.updateState()
  }

  updateState() {
    const selected = this.checkboxTargets.filter(cb => cb.checked)
    const count    = selected.length

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${count}개 선택됨`
    }

    if (this.hasActionBarTarget) {
      this.actionBarTarget.classList.toggle("hidden", count === 0)
    }
  }

  selectedIds() {
    return this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)
  }

  bulkAction(e) {
    const action = e.currentTarget.dataset.action_type
    const ids    = this.selectedIds()
    if (ids.length === 0) return

    if (this.hasFormTarget) {
      const form = this.formTarget
      // hidden input으로 선택된 ID 전달
      ids.forEach(id => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "order_ids[]"
        input.value = id
        form.appendChild(input)
      })
      const actionInput = document.createElement("input")
      actionInput.type  = "hidden"
      actionInput.name  = "action_type"
      actionInput.value = action
      form.appendChild(actionInput)
      form.submit()
    }
  }

  exportCsv() {
    const ids = this.selectedIds()
    if (ids.length === 0) return
    const params = ids.map(id => `order_ids[]=${id}`).join("&")
    window.location.href = `/orders/bulk/export_csv?${params}`
  }
}
