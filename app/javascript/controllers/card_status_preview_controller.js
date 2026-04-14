import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "bg", "border", "text", "card", "cardName"]

  refresh() {
    if (this.hasCardTarget) {
      if (this.hasBgTarget)     this.cardTarget.style.background  = this.bgTarget.value
      if (this.hasBorderTarget) this.cardTarget.style.borderColor = this.borderTarget.value
      if (this.hasTextTarget)   this.cardTarget.style.color       = this.textTarget.value
    }
    if (this.hasCardNameTarget && this.hasNameTarget) {
      this.cardNameTarget.textContent = this.nameTarget.value || "샘플 상태"
    }
  }

  applyPreset(event) {
    const btn = event.currentTarget
    this.bgTarget.value     = btn.dataset.bg
    this.borderTarget.value = btn.dataset.border
    this.textTarget.value   = btn.dataset.text
    this.refresh()
  }
}
