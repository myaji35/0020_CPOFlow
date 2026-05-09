import { Controller } from "@hotwired/stimulus"

// ISS-353 Phase 1 — 멘션 도트 줄 클라이언트 컨트롤러
//
// B1-b 결정 (2026-05-09): 서버는 stateless 렌더, 클라이언트가
// <body data-current-user-id> 읽어 본인 도트에 data-viewer-self="true" 마킹.
// Turbo Stream broadcast로 partial이 교체될 때마다 connect()가 자동 재호출되어
// cross-user broadcast 후에도 viewer-self 마킹이 유지됨.
//
// data-controller="mention-dots mention-viewport"
// 도트 wrapper에 data-action="click->mention-dots#acknowledge" 부여
export default class extends Controller {
  connect() {
    this.markViewerSelf()
  }

  // 본인 user_id의 도트에 data-viewer-self="true" 자동 부여
  markViewerSelf() {
    const currentUserId = document.body.dataset.currentUserId
    if (!currentUserId) return
    this.element.querySelectorAll('[data-user-id]').forEach((el) => {
      if (el.dataset.userId === currentUserId) {
        el.dataset.viewerSelf = "true"
      }
    })
  }

  // 도트 클릭 — 본인이고 unread/viewed_only 상태면 acknowledge
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
