import { Controller } from "@hotwired/stimulus"

// ISS-353 Phase 1 + ISS-354 Phase 2 Wave 3 — 멘션 도트 줄 클라이언트 컨트롤러
//
// Phase 1 책임:
//   - <body data-current-user-id> 읽어 본인 도트에 data-viewer-self="true" 마킹
//   - 본인 도트 클릭 → acknowledge fetch
//
// Phase 2 Wave 3 추가 책임 (T9):
//   - strip 자체 hover (800ms 지연) → /orders/:id/mention_sender_hover fetch
//   - 발신자 본인이면 비빈 응답 → body-direct fixed 패널 렌더 (mention_controller.js의
//     cpoflow-mention-panel 패턴 차용 — 단, 별도 인스턴스로 충돌 회피)
//   - 본인이 발신자가 아니면 서버가 head :no_content → 호버 무시
//
// data-controller="mention-dots mention-viewport"
export default class extends Controller {
  connect() {
    this.markViewerSelf()

    // Phase 2 Wave 3 — 호버 카드 상태
    this._hoverPanel     = null
    this._hoverTimer     = null
    this._fetchedOrderId = null

    // strip 자체 mouseenter/leave (지연 호버)
    this._onMouseEnter = this._onMouseEnterEvent.bind(this)
    this._onMouseLeave = this._onMouseLeaveEvent.bind(this)
    this.element.addEventListener("mouseenter", this._onMouseEnter)
    this.element.addEventListener("mouseleave", this._onMouseLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this._onMouseEnter)
    this.element.removeEventListener("mouseleave", this._onMouseLeave)
    this._closeHover()
    clearTimeout(this._hoverTimer)
  }

  // 본인 user_id의 도트에 data-viewer-self="true" 자동 부여 (Phase 1 유지)
  markViewerSelf() {
    const currentUserId = document.body.dataset.currentUserId
    if (!currentUserId) return
    this.element.querySelectorAll('[data-user-id]').forEach((el) => {
      if (el.dataset.userId === currentUserId) {
        el.dataset.viewerSelf = "true"
      }
    })
  }

  // ── Phase 2 Wave 3: 호버 트리거 ────────────────────────────
  _onMouseEnterEvent(_event) {
    clearTimeout(this._hoverTimer)
    // 800ms 지연 — 단순 마우스 통과 시 fetch 노이즈 방지
    this._hoverTimer = setTimeout(() => this._fetchAndShowHover(), 800)
  }

  _onMouseLeaveEvent(_event) {
    clearTimeout(this._hoverTimer)
    // 약간의 grace — 패널로 마우스 이동 중일 수 있음
    this._hoverTimer = setTimeout(() => {
      // 패널 위에 마우스가 있으면 close 안 함
      if (this._hoverPanel && this._hoverPanel.matches(":hover")) return
      this._closeHover()
    }, 150)
  }

  async _fetchAndShowHover() {
    const orderId = this.element.dataset.mentionViewportOrderIdValue
    if (!orderId) return

    // 같은 카드 재요청 방지 — 캐시된 패널이 있으면 재표시만
    if (this._fetchedOrderId === orderId && this._hoverPanel) {
      this._showPanel(this.element)
      return
    }

    try {
      const res = await fetch(`/orders/${orderId}/mention_sender_hover`, {
        headers: {
          "Accept": "text/html",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || ""
        },
        credentials: "same-origin",
        redirect: "manual"
      })
      // 본인이 발신자가 아니면 204/403 → 무시
      if (!res.ok) return
      const html = (await res.text()).trim()
      if (html.length === 0) return

      this._renderPanel(html)
      this._fetchedOrderId = orderId
    } catch (_err) {
      // silent — 호버 카드 실패는 critical 아님
    }
  }

  _renderPanel(html) {
    if (this._hoverPanel) {
      this._hoverPanel.remove()
      this._hoverPanel = null
    }
    const wrap = document.createElement("div")
    wrap.innerHTML = html
    this._hoverPanel = wrap.firstElementChild
    if (!this._hoverPanel) return

    document.body.appendChild(this._hoverPanel)
    this._showPanel(this.element)

    // 패널 위 마우스로 호버 유지 — leave timer cancel
    this._hoverPanel.addEventListener("mouseenter", () => clearTimeout(this._hoverTimer))
    this._hoverPanel.addEventListener("mouseleave", () => this._closeHover())
  }

  _showPanel(anchorEl) {
    if (!this._hoverPanel) return
    const rect = anchorEl.getBoundingClientRect()
    const panelWidth = 320
    let left = rect.left
    if (left + panelWidth > window.innerWidth - 8) {
      left = Math.max(8, window.innerWidth - panelWidth - 8)
    }
    Object.assign(this._hoverPanel.style, {
      position:     "fixed",
      top:          `${rect.bottom + 6}px`,
      left:         `${left}px`,
      width:        `${panelWidth}px`,
      maxHeight:    "60vh",
      overflowY:    "auto",
      background:   "white",
      border:       "1px solid #e7eaee",
      borderRadius: "8px",
      boxShadow:    "0 10px 25px -5px rgba(12,16,20,0.15), 0 4px 6px -2px rgba(12,16,20,0.08)",
      zIndex:       "2147483647",
      display:      "block"
    })
  }

  _closeHover() {
    if (this._hoverPanel) {
      this._hoverPanel.remove()
      this._hoverPanel = null
      this._fetchedOrderId = null
    }
  }

  // 도트 클릭 — 본인이고 unread/viewed_only 상태면 acknowledge (Phase 1 유지)
  // 카드 onclick(드로어 열기) 충돌 방지를 위해 stopPropagation 필수
  acknowledge(event) {
    const dotEl = event.currentTarget
    const notifId = dotEl.dataset.notificationId
    const isSelf  = dotEl.dataset.viewerSelf === "true"
    if (!isSelf || !notifId) return

    event.stopPropagation()
    event.preventDefault()
    fetch(`/notifications/${notifId}/acknowledge`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
  }
}
