import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]

  preview() {
    const file = this.inputTarget.files[0]
    if (!file) return
    if (file.size > 3 * 1024 * 1024) {
      alert("사진 크기 3MB를 초과했습니다.")
      this.inputTarget.value = ""
      return
    }
    const reader = new FileReader()
    reader.onload = (e) => {
      this.previewTarget.innerHTML = `<img src="${e.target.result}" class="rounded-full object-cover" style="width:80px;height:80px;" alt="미리보기" />`
    }
    reader.readAsDataURL(file)
  }
}
