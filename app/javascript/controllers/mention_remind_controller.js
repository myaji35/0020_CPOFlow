import { Controller } from "@hotwired/stimulus"

// ISS-354 Phase 2 Wave 3 (T12) — 발신자 호버 카드 내 리마인드 버튼 컨트롤러
//
// 사용처: app/views/orders/_mention_sender_hover.html.erb
//
// 역할:
//   - "리마인드 모두 보내기" 버튼 → POST /orders/:id/mention_remind_all
//   - 행별 push 버튼          → POST /orders/:id/mention_remind_one/:user_id
//   - 응답은 turbo_stream.replace("sender-hover-:order_id", ...) → DOM 자동 갱신
//
// data-controller="mention-remind"
// data-mention-remind-order-id-value="<order.id>"
//
// 행 버튼: data-action="click->mention-remind#sendOne"
//          data-mention-remind-receiver-id-param="<user.id>"
// 일괄 버튼: data-action="click->mention-remind#sendAll"
export default class extends Controller {
  static values = { orderId: Number }

  sendAll(event) {
    event.preventDefault()
    event.stopPropagation()
    this._post(`/orders/${this.orderIdValue}/mention_remind_all`)
  }

  sendOne(event) {
    event.preventDefault()
    event.stopPropagation()
    const receiverId = event.params.receiverId
    if (!receiverId) return
    this._post(`/orders/${this.orderIdValue}/mention_remind_one/${receiverId}`)
  }

  async _post(url) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "",
          "Accept":       "text/vnd.turbo-stream.html",
          "Content-Type": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({})
      })
      if (!res.ok) {
        console.warn("[mention-remind] failed:", res.status)
        return
      }
      const html = await res.text()
      // Turbo Stream 응답 → DOM 자동 갱신
      if (window.Turbo && typeof window.Turbo.renderStreamMessage === "function") {
        window.Turbo.renderStreamMessage(html)
      }
    } catch (err) {
      console.error("[mention-remind]", err)
    }
  }
}
