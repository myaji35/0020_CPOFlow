import { Controller } from "@hotwired/stimulus"

// 직원 폼 내 부서 인라인 추가/삭제 모달
// data-controller="department-manager"
export default class extends Controller {
  static targets = ["select", "modal", "list", "addInput", "addCompany", "addError", "deleteError"]
  static values  = { url: String }

  // 모달 열기
  open(e) {
    e.preventDefault()
    this.modalTarget.classList.remove("hidden")
    this.addInputTarget.value = ""
    this.addErrorTarget.textContent = ""
    this.deleteErrorTarget.textContent = ""
    this.loadList()
  }

  // 모달 닫기
  close(e) {
    e?.preventDefault()
    this.modalTarget.classList.add("hidden")
  }

  // 모달 바깥 클릭 시 닫기
  backdropClose(e) {
    if (e.target === this.modalTarget) this.close()
  }

  // 부서 목록 로드
  async loadList() {
    const res  = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    const data = await res.json()
    this.renderList(data)
    // 현재 select 옵션 동기화
    this.syncSelect(data)
  }

  renderList(departments) {
    this.listTarget.innerHTML = departments.length === 0
      ? '<p class="text-xs text-gray-400 py-2 text-center">등록된 부서가 없습니다.</p>'
      : departments.map(d => `
        <div class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 group" data-dept-id="${d.id}">
          <div class="min-w-0">
            <span class="text-sm text-gray-800 dark:text-gray-200">${d.name}</span>
            <span class="ml-2 text-[10px] text-gray-400">${d.company}</span>
            ${d.employee_count > 0 ? `<span class="ml-1 text-[10px] text-blue-500">${d.employee_count}명</span>` : ""}
          </div>
          <button type="button"
                  class="opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-red-50 dark:hover:bg-red-900/30 text-gray-300 hover:text-red-500"
                  title="삭제"
                  data-action="click->department-manager#deleteDept"
                  data-id="${d.id}"
                  data-name="${d.name}"
                  data-count="${d.employee_count}">
            <svg class="w-3.5 h-3.5 pointer-events-none" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/>
            </svg>
          </button>
        </div>`).join("")
  }

  // select 옵션을 최신 부서 목록과 동기화
  syncSelect(departments) {
    const current = this.selectTarget.value
    const blank   = this.selectTarget.querySelector("option[value='']")
    this.selectTarget.innerHTML = ""
    if (blank) this.selectTarget.appendChild(blank)
    departments.forEach(d => {
      const opt = document.createElement("option")
      opt.value = d.id
      opt.textContent = d.name
      if (String(d.id) === String(current)) opt.selected = true
      this.selectTarget.appendChild(opt)
    })
  }

  // 부서 추가
  async addDept(e) {
    e.preventDefault()
    const name      = this.addInputTarget.value.trim()
    const companyId = this.addCompanyTarget.value
    this.addErrorTarget.textContent = ""

    if (!name) {
      this.addErrorTarget.textContent = "부서명을 입력해주세요."
      return
    }

    const res  = await fetch(this.urlValue, {
      method:  "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken(), Accept: "application/json" },
      body:    JSON.stringify({ name, company_id: companyId })
    })
    const data = await res.json()

    if (res.ok) {
      this.addInputTarget.value = ""
      this.loadList()
    } else {
      this.addErrorTarget.textContent = data.error || "추가 실패"
    }
  }

  // 부서 삭제
  async deleteDept(e) {
    const btn   = e.currentTarget
    const id    = btn.dataset.id
    const name  = btn.dataset.name
    const count = parseInt(btn.dataset.count, 10)
    this.deleteErrorTarget.textContent = ""

    if (count > 0) {
      this.deleteErrorTarget.textContent = `"${name}"에 소속 직원이 ${count}명 있어 삭제할 수 없습니다.`
      return
    }

    if (!confirm(`"${name}" 부서를 삭제하시겠습니까?`)) return

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
