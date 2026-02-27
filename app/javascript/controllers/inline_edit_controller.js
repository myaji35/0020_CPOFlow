import { Controller } from "@hotwired/stimulus"

// 오더 목록 인라인 빠른 수정 — 납기일·상태
export default class extends Controller {
  static values = { url: String }

  saveDueDate(e) {
    this.#patch({ due_date: e.target.value })
  }

  saveStatus(e) {
    this.#patch({ status: e.target.value })
  }

  #patch(body) {
    const csrf = document.querySelector('meta[name="csrf-token"]').content
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ order: body })
    })
    .then(r => r.json())
    .then(data => {
      if (!data.success) {
        alert("저장 실패: " + (data.errors || []).join(", "))
        location.reload()
      }
    })
    .catch(() => { alert("네트워크 오류가 발생했습니다."); location.reload() })
  }
}
