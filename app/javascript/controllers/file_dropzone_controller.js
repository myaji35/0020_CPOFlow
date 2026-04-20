import { Controller } from "@hotwired/stimulus"

// 파일 드래그 & 드롭 업로드 영역
// data-controller="file-dropzone"
// data-file-dropzone-max-size-value="26214400" (25MB)
// data-file-dropzone-auto-submit-value="true"
//
// Targets:
//   input   : <input type="file" multiple>
//   label   : 상태 표시용 <span> 또는 텍스트 영역
//   zone    : 드래그 오버 시 하이라이트될 래퍼 (없으면 element 자체)
//   submit  : 자동 제출 미사용 시 수동 제출 버튼 (선택)
export default class extends Controller {
  static targets = ["input", "label", "zone", "submit"]
  static values  = {
    maxSize:    { type: Number,  default: 25 * 1024 * 1024 },
    autoSubmit: { type: Boolean, default: true },
    idleLabel:  { type: String,  default: "파일 선택 또는 드래그" }
  }

  connect() {
    this._dragDepth = 0
    this._bound = {
      dragenter: this._onDragEnter.bind(this),
      dragover:  this._onDragOver.bind(this),
      dragleave: this._onDragLeave.bind(this),
      drop:      this._onDrop.bind(this),
      change:    this._onChange.bind(this),
      winDragover: (e) => e.preventDefault(),
      winDrop:     (e) => e.preventDefault()
    }

    const z = this._zoneEl()
    z.addEventListener("dragenter", this._bound.dragenter)
    z.addEventListener("dragover",  this._bound.dragover)
    z.addEventListener("dragleave", this._bound.dragleave)
    z.addEventListener("drop",      this._bound.drop)

    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("change", this._bound.change)
    }

    // 브라우저 기본동작(페이지를 파일로 열기) 차단 — 드롭존 밖에 떨어뜨려도 안전
    window.addEventListener("dragover", this._bound.winDragover)
    window.addEventListener("drop",     this._bound.winDrop)
  }

  disconnect() {
    const z = this._zoneEl()
    z.removeEventListener("dragenter", this._bound.dragenter)
    z.removeEventListener("dragover",  this._bound.dragover)
    z.removeEventListener("dragleave", this._bound.dragleave)
    z.removeEventListener("drop",      this._bound.drop)
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("change", this._bound.change)
    }
    window.removeEventListener("dragover", this._bound.winDragover)
    window.removeEventListener("drop",     this._bound.winDrop)
  }

  _zoneEl() {
    return this.hasZoneTarget ? this.zoneTarget : this.element
  }

  _onDragEnter(e) {
    e.preventDefault()
    e.stopPropagation()
    this._dragDepth++
    this._zoneEl().classList.add("ring-2", "ring-[#00A1E0]", "bg-blue-50/50")
  }

  _onDragOver(e) {
    e.preventDefault()
    e.stopPropagation()
    if (e.dataTransfer) e.dataTransfer.dropEffect = "copy"
  }

  _onDragLeave(e) {
    e.preventDefault()
    e.stopPropagation()
    this._dragDepth = Math.max(0, this._dragDepth - 1)
    if (this._dragDepth === 0) this._resetZone()
  }

  _onDrop(e) {
    e.preventDefault()
    e.stopPropagation()
    this._dragDepth = 0
    this._resetZone()

    const files = e.dataTransfer?.files
    if (!files || !files.length) return
    if (!this.hasInputTarget) return

    const valid = this._filterOversize(files)
    if (!valid.length) return

    // DataTransfer로 FileList 생성 → input에 할당
    const dt = new DataTransfer()
    valid.forEach(f => dt.items.add(f))
    this.inputTarget.files = dt.files

    this._updateLabel(valid)

    if (this.autoSubmitValue) this._submit()
  }

  _onChange() {
    if (!this.hasInputTarget) return
    const valid = this._filterOversize(this.inputTarget.files)
    if (!valid.length) {
      this.inputTarget.value = ""
      this._updateLabel([])
      return
    }
    if (valid.length !== this.inputTarget.files.length) {
      const dt = new DataTransfer()
      valid.forEach(f => dt.items.add(f))
      this.inputTarget.files = dt.files
    }
    this._updateLabel(valid)
    if (this.autoSubmitValue) this._submit()
  }

  _filterOversize(fileList) {
    const arr = Array.from(fileList)
    const over = arr.filter(f => f.size > this.maxSizeValue)
    if (over.length) {
      const names = over.map(f => `${f.name} (${(f.size / 1024 / 1024).toFixed(1)}MB)`).join(", ")
      this._setLabelError(`크기 초과 (최대 25MB): ${names}`)
      return arr.filter(f => f.size <= this.maxSizeValue)
    }
    return arr
  }

  _updateLabel(files) {
    if (!this.hasLabelTarget) return
    if (!files.length) {
      this.labelTarget.textContent = this.idleLabelValue
      this.labelTarget.classList.remove("text-[#00A1E0]", "font-medium", "text-red-500")
      return
    }
    const names = files.map(f => f.name)
    const text  = files.length === 1
      ? names[0]
      : `${files.length}개 파일: ${names.join(", ")}`
    this.labelTarget.textContent = text.length > 60 ? text.slice(0, 57) + "..." : text
    this.labelTarget.classList.add("text-[#00A1E0]", "font-medium")
    this.labelTarget.classList.remove("text-red-500")
  }

  _setLabelError(msg) {
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent = `⚠ ${msg}`
    this.labelTarget.classList.add("text-red-500", "font-medium")
    this.labelTarget.classList.remove("text-[#00A1E0]")
  }

  _resetZone() {
    this._zoneEl().classList.remove("ring-2", "ring-[#00A1E0]", "bg-blue-50/50")
  }

  _submit() {
    const form = this.element.closest("form") || this.element.querySelector("form")
    if (!form) return
    // Turbo가 requestSubmit을 선호
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }
}
