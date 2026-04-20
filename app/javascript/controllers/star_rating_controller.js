import { Controller } from "@hotwired/stimulus"

// star_rating_controller.js
// 별점 1~5 선택 (호버/클릭/hidden input 동기화)
export default class extends Controller {
  static targets = ["star", "input", "label"]
  static values  = { rating: { type: Number, default: 0 } }

  connect() {
    this.render(this.ratingValue)
  }

  hover(event) {
    const val = parseInt(event.currentTarget.dataset.value, 10)
    this.render(val, true)
  }

  leave() {
    this.render(this.ratingValue)
  }

  select(event) {
    const val = parseInt(event.currentTarget.dataset.value, 10)
    this.ratingValue = val
    this.inputTarget.value = val
    this.render(val)
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.labelFor(val)
    }
  }

  render(activeVal, isHover = false) {
    this.starTargets.forEach((star) => {
      const val = parseInt(star.dataset.value, 10)
      const filled = val <= activeVal

      // SVG stroke/fill 토글
      const paths = star.querySelectorAll("path, polygon")
      paths.forEach((p) => {
        if (filled) {
          p.setAttribute("fill", isHover ? "#F4A83A" : "#F4A83A")
          p.setAttribute("stroke", "#F4A83A")
        } else {
          p.setAttribute("fill", "none")
          p.setAttribute("stroke", "currentColor")
        }
      })

      // 색상 클래스
      star.classList.toggle("text-warning", filled)
      star.classList.toggle("text-gray-300", !filled)
    })
  }

  labelFor(val) {
    const labels = { 1: "매우 불만족", 2: "불만족", 3: "보통", 4: "만족", 5: "매우 만족" }
    return labels[val] || ""
  }
}
