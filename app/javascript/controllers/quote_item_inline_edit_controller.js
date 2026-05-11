import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("td[data-item-id]").forEach((td) => {
      td.addEventListener("dblclick", () => this.startEdit(td))
    })
  }

  startEdit(td) {
    if (td.dataset.editing === "1") return
    td.dataset.editing = "1"

    const original = (td.querySelector(".quote-cell-text")?.textContent ?? td.textContent).trim()
    const field = td.dataset.field
    const id = td.dataset.itemId
    const isLong = field === "description" || field === "remarks"
    const input = document.createElement(isLong ? "textarea" : "input")
    input.value = original
    input.className = "w-full text-xs border border-[#00A1E0] rounded px-1 py-0.5"
    if (isLong) input.rows = 3

    td.innerHTML = ""
    td.appendChild(input)
    input.focus()

    let saved = false
    const finishSave = () => {
      if (saved) return
      saved = true
      this.save(td, id, field, input.value).catch(() => {
        td.textContent = original
        td.dataset.editing = "0"
      })
    }
    const cancel = () => {
      saved = true
      td.textContent = original
      td.dataset.editing = "0"
    }

    input.addEventListener("blur", finishSave)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.preventDefault()
        cancel()
        input.blur()
      }
      if (e.key === "Enter" && !isLong) {
        e.preventDefault()
        input.blur()
      }
    })
  }

  async save(td, id, field, value) {
    const orderId = this.element.id
      .replace("drawer-panel-", "")
      .replace("-quote_items", "")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const fd = new FormData()
    fd.set("field", field)
    fd.set("value", value)
    fd.set("authenticity_token", token)
    const res = await fetch(`/orders/${orderId}/quote_items/${id}`, {
      method: "PATCH",
      body: fd,
      headers: { Accept: "text/vnd.turbo-stream.html" }
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const html = await res.text()
    Turbo.renderStreamMessage(html)
    td.dataset.editing = "0"
  }
}
