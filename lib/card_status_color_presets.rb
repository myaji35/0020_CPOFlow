# frozen_string_literal: true

# 12개 색상 프리셋 — Settings 편집 모달에서 원클릭 선택 지원.
# 각 세트는 {key, name, bg, border, text} 구조 (bg/border/text는 HEX #RRGGBB).
module CardStatusColorPresets
  ALL = [
    { key: "gray",   name: "회색",   bg: "#FAFAFA", border: "#E5E7EB", text: "#374151" },
    { key: "red",    name: "빨강",   bg: "#FFF1F2", border: "#FECDD3", text: "#991B1B" },
    { key: "orange", name: "주황",   bg: "#FFF7ED", border: "#FED7AA", text: "#9A3412" },
    { key: "amber",  name: "황색",   bg: "#FEFCE8", border: "#FEF08A", text: "#854D0E" },
    { key: "green",  name: "초록",   bg: "#F0FDF4", border: "#BBF7D0", text: "#14532D" },
    { key: "teal",   name: "청록",   bg: "#F0FDFA", border: "#99F6E4", text: "#134E4A" },
    { key: "blue",   name: "파랑",   bg: "#EFF6FF", border: "#BFDBFE", text: "#1E3A8A" },
    { key: "indigo", name: "남색",   bg: "#EEF2FF", border: "#C7D2FE", text: "#312E81" },
    { key: "purple", name: "보라",   bg: "#F5F3FF", border: "#DDD6FE", text: "#5B21B6" },
    { key: "pink",   name: "분홍",   bg: "#FDF2F8", border: "#FBCFE8", text: "#9D174D" },
    { key: "brown",  name: "갈색",   bg: "#FAF5EF", border: "#E7D3B8", text: "#6B3F00" },
    { key: "slate",  name: "진회색", bg: "#F1F5F9", border: "#CBD5E1", text: "#1E293B" }
  ].freeze

  def self.find(key)
    ALL.find { |p| p[:key] == key.to_s }
  end
end
