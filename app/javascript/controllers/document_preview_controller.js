import { Controller } from "@hotwired/stimulus"

// 첨부 문서 썸네일 클릭 시 큰 미리보기 전환
// data-controller="document-preview"
// Targets:
//   viewer : 큰 미리보기 컨테이너
export default class extends Controller {
  static targets = ["viewer"]

  switch({ params: { blobUrl, contentType, filename } }) {
    if (!this.hasViewerTarget) return

    let html
    if (contentType && contentType.startsWith("image/")) {
      html = `<img src="${blobUrl}" class="max-w-full max-h-[500px] object-contain" alt="${filename}">`
    } else if (contentType === "application/pdf") {
      html = `<iframe src="${blobUrl}" class="w-full h-[500px] border-0" title="${filename}"></iframe>`
    } else {
      html = `
        <div class="text-center p-6">
          <svg class="w-16 h-16 mx-auto text-gray-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
            <polyline points="14 2 14 8 20 8"/>
          </svg>
          <p class="text-sm text-gray-500 mt-2">${filename}</p>
          <a href="${blobUrl}?disposition=attachment" class="text-xs text-primary mt-2 inline-block">다운로드</a>
        </div>`
    }

    this.viewerTarget.innerHTML = html
  }
}
