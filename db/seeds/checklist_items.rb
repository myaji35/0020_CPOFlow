# ISS-330 옵션A: 클라이언트 프롬프트 예시 그대로 시드
# 호출: bin/rails runner "load Rails.root.join('db/seeds/checklist_items.rb')"
items = [
  {
    code: "AQ_GRADE", name: "AQ 등급", name_en: "AQ Grade", category: "quality",
    prompt_hint: "Acceptance Quality 등급 — 문서에서 A/B/C/Reject 중 어느 등급인지 추출",
    allowed_values_array: %w[A B C Reject],
    required: true, position: 10
  },
  {
    code: "DRAWING_NO", name: "도면 번호", name_en: "Drawing No.", category: "drawing",
    prompt_hint: "도면번호 (예: DWG-2026-001, A-07457726-D, ITEM5/SHEET2 등) — 모두 추출",
    required: false, position: 20
  },
  {
    code: "URGENCY", name: "긴급도", name_en: "Urgency", category: "urgency",
    prompt_hint: "마감일까지 남은 일수 — D-1/D-3/D-7/D-30 분류",
    allowed_values_array: %w[D-1 D-3 D-7 D-30 NORMAL],
    required: true, position: 30
  },
  {
    code: "CERT_REQ", name: "필수 인증", name_en: "Required Certifications", category: "cert",
    prompt_hint: "요구되는 인증 (CE, UL, KC, ISO9001, NEMA, ATEX, IECEx 등) — 배열로",
    required: false, position: 40
  },
  {
    code: "REFERENCE_DOCS", name: "참조 문서", name_en: "Reference Documents", category: "general",
    prompt_hint: "REFERENCE DOCUMENTS 항목에 나열된 도면/규격 모두 — 배열",
    required: false, position: 50
  }
]

items.each do |attrs|
  arr = attrs.delete(:allowed_values_array)
  ci = ChecklistItem.find_or_initialize_by(code: attrs[:code])
  ci.assign_attributes(attrs)
  ci.allowed_values_array = arr if arr
  ci.save!
  puts "  CHECKLIST #{attrs[:code]}: #{ci.persisted? ? 'OK' : 'FAIL'}"
end
puts "Total ChecklistItem: #{ChecklistItem.count}"
