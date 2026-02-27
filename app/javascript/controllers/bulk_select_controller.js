import { Controller } from "@hotwired/stimulus"

// 주문 목록 일괄 처리 — 체크박스 선택 및 하단 액션 바 제어
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "actionBar", "count", "form", "statusSelect", "assignSelect"]

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

  bulkAction() {
    const ids    = this.selectedIds()
    if (ids.length === 0) return
    const status = this.hasStatusSelectTarget ? this.statusSelectTarget.value : ""
    if (!status) { alert("상태를 선택해주세요."); return }

    const form = this.formTarget
    this.#clearHidden(form, ["order_ids[]", "action_type", "status"])
    ids.forEach(id => this.#addHidden(form, "order_ids[]", id))
    this.#addHidden(form, "action_type", "status")
    this.#addHidden(form, "status", status)
    form.submit()
  }

  bulkAssign() {
    const ids    = this.selectedIds()
    if (ids.length === 0) return
    const userId = this.hasAssignSelectTarget ? this.assignSelectTarget.value : ""
    if (!userId) { alert("담당자를 선택해주세요."); return }

    const form = this.formTarget
    this.#clearHidden(form, ["order_ids[]", "action_type", "user_id"])
    ids.forEach(id => this.#addHidden(form, "order_ids[]", id))
    this.#addHidden(form, "action_type", "assign")
    this.#addHidden(form, "user_id", userId)
    form.submit()
  }

  exportCsv() {
    const ids = this.selectedIds()
    if (ids.length === 0) return
    const params = ids.map(id => `order_ids[]=${id}`).join("&")
    window.location.href = `/orders/bulk/export_csv?${params}`
  }

  clearAll() {
    this.checkboxTargets.forEach(cb => cb.checked = false)
    if (this.hasSelectAllTarget) this.selectAllTarget.checked = false
    this.updateState()
  }

  #addHidden(form, name, value) {
    const i = document.createElement("input")
    i.type = "hidden"; i.name = name; i.value = value
    form.appendChild(i)
  }

  #clearHidden(form, names) {
    names.forEach(name => {
      form.querySelectorAll(`input[name="${name}"]`).forEach(el => el.remove())
    })
  }
}
