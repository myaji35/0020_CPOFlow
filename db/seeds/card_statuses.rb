# frozen_string_literal: true

# 7개 샘플 프리셋 — 스펙 §4 표와 동일
card_status_presets = [
  { key: "urgent",  name: "긴급",     bg: "#FFF1F2", border: "#FECDD3", text: "#991B1B",
    position: 1, is_system: true,  is_default: false,
    auto_rule: { when: "due_date", operator: "lte", value: 3 }, auto_priority: 30 },
  { key: "high",    name: "높음",     bg: "#FFF7ED", border: "#FED7AA", text: "#9A3412",
    position: 2, is_system: true,  is_default: false,
    auto_rule: { when: "due_date", operator: "lte", value: 7 }, auto_priority: 20 },
  { key: "normal",  name: "보통",     bg: "#FAFAFA", border: "#E5E7EB", text: "#374151",
    position: 3, is_system: true,  is_default: true,
    auto_rule: nil, auto_priority: 0 },
  { key: "low",     name: "낮음",     bg: "#F0FDF4", border: "#BBF7D0", text: "#14532D",
    position: 4, is_system: true,  is_default: false,
    auto_rule: nil, auto_priority: 0 },
  { key: "vip",     name: "VIP 고객", bg: "#F5F3FF", border: "#DDD6FE", text: "#5B21B6",
    position: 5, is_system: false, is_default: false,
    auto_rule: nil, auto_priority: 0 },
  { key: "hold",    name: "대기/보류", bg: "#FEFCE8", border: "#FEF08A", text: "#854D0E",
    position: 6, is_system: false, is_default: false,
    auto_rule: nil, auto_priority: 0 },
  { key: "overdue", name: "기한초과", bg: "#FEE2E2", border: "#FCA5A5", text: "#7F1D1D",
    position: 7, is_system: false, is_default: false,
    auto_rule: { when: "due_date", operator: "lte", value: 0 }, auto_priority: 40 }
].freeze

card_status_presets.each do |p|
  cs = CardStatus.find_or_initialize_by(key: p[:key])
  cs.assign_attributes(
    name:          p[:name],
    bg_color:      p[:bg],
    border_color:  p[:border],
    text_color:    p[:text],
    position:      p[:position],
    is_system:     p[:is_system],
    is_default:    p[:is_default],
    auto_rule:     p[:auto_rule]&.to_json,
    auto_priority: p[:auto_priority]
  )
  cs.save!
end
puts "[seed] CardStatus: #{CardStatus.count}개 seeded"
