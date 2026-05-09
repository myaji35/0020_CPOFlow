import { Controller } from "@hotwired/stimulus"

// ISS-353 Phase 1 — 뷰포트 5초 연속 노출 시 자동 viewed_at 기록
//
// IntersectionObserver(threshold: 0.5)로 strip이 화면에 50% 이상 노출되는지 감시.
// 본인(data-viewer-self="true")이고 unread 상태인 도트만 대상.
// 5초(threshold value, 기본 5000ms) 도달 시 PATCH /notifications/:id/view?duration=5.
// 빠른 스크롤(<5s)은 setTimeout 취소로 미기록 (안티 게이밍 + 정확성).
// 같은 notification은 fired Set으로 중복 호출 차단.
//
// data-controller="mention-dots mention-viewport"
// data-mention-viewport-order-id-value="<order.id>"
// data-mention-viewport-threshold-value="5000"
export default class extends Controller {
  static values = {
    orderId: Number,
    threshold: { type: Number, default: 5000 }
  }

  connect() {
    this.timers = new Map()
    this.fired  = new Set()
    this.observer = new IntersectionObserver(this.onIntersect.bind(this), {
      threshold: 0.5
    })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.timers.forEach((t) => clearTimeout(t))
    this.timers.clear()
  }

  onIntersect(entries) {
    entries.forEach((entry) => {
      const selfDots = this.element.querySelectorAll('[data-viewer-self="true"][data-state="unread"]')
      selfDots.forEach((dot) => {
        const nid = dot.dataset.notificationId
        if (!nid || this.fired.has(nid)) return

        if (entry.isIntersecting) {
          if (!this.timers.has(nid)) {
            const t = setTimeout(() => this.fireView(nid), this.thresholdValue)
            this.timers.set(nid, t)
          }
        } else {
          const t = this.timers.get(nid)
          if (t) { clearTimeout(t); this.timers.delete(nid) }
        }
      })
    })
  }

  fireView(notifId) {
    if (this.fired.has(notifId)) return
    this.fired.add(notifId)
    this.timers.delete(notifId)
    fetch(`/notifications/${notifId}/view?duration=5`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
        "Accept": "application/json"
      }
    })
  }
}
