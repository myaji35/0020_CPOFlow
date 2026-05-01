import { Controller } from "@hotwired/stimulus"

// 첨부 문서 미리보기:
//  - 저장된 첨부 썸네일 클릭 → 큰 미리보기 전환
//  - 파일 선택(input change) → 즉시 클라이언트 미리보기 (저장 전)
//
// data-controller="document-preview"
// Targets:
//   viewer : 큰 미리보기 컨테이너
//   input  : <input type="file"> (선택 시 즉시 미리보기)
//   empty  : 빈 상태 안내 (선택 후 숨김)
//   thumbs : 새로 선택한 파일 썸네일 그리드 (선택사항)
export default class extends Controller {
  static targets = ["viewer", "input", "empty", "thumbs"]

  connect() {
    this._objectUrls = []
  }

  disconnect() {
    // 메모리 누수 방지 — object URL 해제
    this._objectUrls.forEach(url => URL.revokeObjectURL(url))
    this._objectUrls = []
  }

  // 저장된 첨부 썸네일 클릭
  switch({ params: { blobUrl, contentType, filename } }) {
    if (!this.hasViewerTarget) return
    this.viewerTarget.innerHTML = this._renderHtml(blobUrl, contentType, filename)
    if (this.hasEmptyTarget) this.emptyTarget.classList.add("hidden")
  }

  // input file change — 새로 선택한 파일 즉시 미리보기
  onFileSelect(event) {
    const files = Array.from(event.target.files || [])
    if (files.length === 0) return

    // 빈 상태 안내 숨김
    if (this.hasEmptyTarget) this.emptyTarget.classList.add("hidden")

    // 첫 파일을 큰 미리보기로
    const first = files[0]
    if (this.hasViewerTarget) {
      const url = URL.createObjectURL(first)
      this._objectUrls.push(url)
      this.viewerTarget.innerHTML = this._renderHtml(url, first.type, first.name, true)
    }

    // 여러 파일 선택 시 썸네일 (선택사항)
    if (this.hasThumbsTarget && files.length > 1) {
      this.thumbsTarget.innerHTML = files.map((f, idx) => {
        const url = URL.createObjectURL(f)
        this._objectUrls.push(url)
        const isImage = f.type && f.type.startsWith("image/")
        const thumb = isImage
          ? `<img src="${url}" class="w-full h-full object-cover rounded" alt="${this._esc(f.name)}">`
          : `<span class="text-xs text-gray-500 truncate w-full text-center leading-tight">${this._esc(f.name)}</span>`
        return `<button type="button"
                  data-action="click->document-preview#switchToObjectUrl"
                  data-document-preview-blob-url-param="${url}"
                  data-document-preview-content-type-param="${this._esc(f.type)}"
                  data-document-preview-filename-param="${this._esc(f.name)}"
                  class="aspect-square bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded hover:border-[#00A1E0] transition-colors p-1 flex items-center justify-center overflow-hidden ring-2 ring-amber-400">
                  ${thumb}
                </button>`
      }).join("")
      this.thumbsTarget.classList.remove("hidden")
    }
  }

  switchToObjectUrl(event) {
    const { blobUrl, contentType, filename } = event.params
    if (!this.hasViewerTarget) return
    this.viewerTarget.innerHTML = this._renderHtml(blobUrl, contentType, filename, true)
  }

  // ── private ──
  _renderHtml(url, contentType, filename, unsaved = false) {
    const badge = unsaved
      ? `<span class="absolute top-2 left-2 inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800 z-10">저장 전 미리보기</span>`
      : ""

    let body
    if (contentType && contentType.startsWith("image/")) {
      body = `<img src="${url}" class="max-w-full max-h-[500px] object-contain" alt="${this._esc(filename)}">`
    } else if (contentType === "application/pdf") {
      body = `<iframe src="${url}" class="w-full h-[500px] border-0" title="${this._esc(filename)}"></iframe>`
    } else {
      body = `
        <div class="text-center p-6">
          <svg class="w-16 h-16 mx-auto text-gray-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
            <polyline points="14 2 14 8 20 8"/>
          </svg>
          <p class="text-sm text-gray-500 mt-2">${this._esc(filename)}</p>
          ${unsaved ? '<p class="text-xs text-amber-600 mt-1">저장 후 다운로드 가능합니다</p>' : `<a href="${url}?disposition=attachment" class="text-xs text-primary mt-2 inline-block">다운로드</a>`}
        </div>`
    }
    return `<div class="relative w-full h-full flex items-center justify-center">${badge}${body}</div>`
  }

  _esc(str) {
    return String(str ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
