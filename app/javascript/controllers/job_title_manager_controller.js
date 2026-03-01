import { Controller } from "@hotwired/stimulus"

// 직원 폼 내 직책 인라인 추가/삭제 모달
// data-controller="job-title-manager"
export default class extends Controller {
  static targets = ["select", "modal", "list", "addInput", "addError", "deleteError"]
  static values  = { url: String }

  open(e) {
    e.preventDefault()
    this.modalTarget.classList.remove("hidden")
    this.addInputTarget.value = ""
    this.addErrorTarget.textContent = ""
    this.deleteErrorTarget.textContent = ""
    this.loadList()
  }

  close(e) {
    e?.preventDefault()
    this.modalTarget.classList.add("hidden")
  }

  backdropClose(e) {
    if (e.target === this.modalTarget) this.close()
  }

  async loadList() {
    const res  = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    const data = await res.json()
    this.renderList(data)
    this.syncSelect(data)
  }

  renderList(jobTitles) {
    this.listTarget.innerHTML = jobTitles.length === 0
      ? '<p class="text-xs text-gray-400 py-2 text-center">등록된 직책이 없습니다.</p>'
      : jobTitles.map(jt => `
        <div class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 group">
          <div class="min-w-0">
            <span class="text-sm text-gray-800 dark:text-gray-200">${jt.name}</span>
            ${jt.employee_count > 0 ? `<span class="ml-2 text-[10px] text-blue-500">${jt.employee_count}명</span>` : ""}
          </div>
          <button type="button"
                  class="opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-red-50 dark:hover:bg-red-900/30 text-gray-300 hover:text-red-500"
                  title="삭제"
                  data-action="click->job-title-manager#deleteJobTitle"
                  data-id="${jt.id}"
                  data-name="${jt.name}"
                  data-count="${jt.employee_count}">
            <svg class="w-3.5 h-3.5 pointer-events-none" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/>
            </svg>
          </button>
        </div>`).join("")
  }

  syncSelect(jobTitles) {
    const current = this.selectTarget.value
    const blank   = this.selectTarget.querySelector("option[value='']")
    this.selectTarget.innerHTML = ""
    if (blank) this.selectTarget.appendChild(blank)
    jobTitles.forEach(jt => {
      const opt = document.createElement("option")
      opt.value = jt.name
      opt.textContent = jt.name
      if (jt.name === current) opt.selected = true
      this.selectTarget.appendChild(opt)
    })
  }

  async addJobTitle(e) {
    e.preventDefault()
    const name = this.addInputTarget.value.trim()
    this.addErrorTarget.textContent = ""

    if (!name) {
      this.addErrorTarget.textContent = "직책명을 입력해주세요."
      return
    }

    const res  = await fetch(this.urlValue, {
      method:  "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken(), Accept: "application/json" },
      body:    JSON.stringify({ name })
    })
    const data = await res.json()

    if (res.ok) {
      this.addInputTarget.value = ""
      this.loadList()
    } else {
      this.addErrorTarget.textContent = data.error || "추가 실패"
    }
  }

  async deleteJobTitle(e) {
    const btn   = e.currentTarget
    const id    = btn.dataset.id
    const name  = btn.dataset.name
    const count = parseInt(btn.dataset.count, 10)
    this.deleteErrorTarget.textContent = ""

    if (count > 0) {
      this.deleteErrorTarget.textContent = `"${name}" 직책의 직원이 ${count}명 있어 삭제할 수 없습니다.`
      return
    }

    if (!confirm(`"${name}" 직책을 삭제하시겠습니까?`)) return

    const res  = await fetch(`${this.urlValue}/${id}`, {
      method:  "DELETE",
      headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" }
    })
    const data = await res.json()

    if (res.ok) {
      this.loadList()
    } else {
      this.deleteErrorTarget.textContent = data.error || "삭제 실패"
    }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
