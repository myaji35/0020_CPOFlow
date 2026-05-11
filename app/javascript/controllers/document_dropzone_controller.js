import { Controller } from "@hotwired/stimulus"

// PATCH AJAX 방식 파일 업로드 드롭존
// data-controller="document-dropzone"
// data-document-dropzone-url-value="/employees/:id" (PATCH 엔드포인트)
export default class extends Controller {
  static targets = ["zone", "label", "input"]
  static values = { url: String }

  openFileDialog(event) {
    if (event.target === this.inputTarget) return
    this.inputTarget.click()
  }

  dragOver(e) {
    e.preventDefault()
    this.zoneTarget.classList.add("border-[#00A1E0]", "bg-blue-50/40")
  }

  dragLeave(e) {
    this.zoneTarget.classList.remove("border-[#00A1E0]", "bg-blue-50/40")
  }

  drop(e) {
    e.preventDefault()
    this.zoneTarget.classList.remove("border-[#00A1E0]", "bg-blue-50/40")
    const files = e.dataTransfer?.files
    if (files && files.length) this.upload(files)
  }

  fileSelected() {
    if (this.inputTarget.files.length) this.upload(this.inputTarget.files)
  }

  async upload(files) {
    const fd = new FormData()
    Array.from(files).forEach(f => fd.append("documents[]", f))
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) fd.set("authenticity_token", token)

    this.labelTarget.textContent = `📎 업로드 중... (${files.length}건)`
    try {
      const res = await fetch(this.urlValue, {
        method: "PATCH",
        body: fd,
        headers: { Accept: "text/vnd.turbo-stream.html, text/html" }
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const ct = res.headers.get("content-type") || ""
      if (ct.includes("turbo-stream")) {
        const html = await res.text()
        Turbo.renderStreamMessage(html)
      } else {
        location.reload()
      }
    } catch (err) {
      console.error("[document-dropzone] upload failed", err)
      alert("파일 업로드 실패: " + err.message)
    } finally {
      this.labelTarget.textContent = "📎 파일을 드래그하거나 클릭하여 추가"
      this.inputTarget.value = ""
    }
  }
}
