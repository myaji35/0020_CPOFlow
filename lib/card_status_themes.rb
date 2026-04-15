# frozen_string_literal: true

# 칸반 범례 컬러 테마 — 한 번 클릭으로 전체 카드 상태에 일관된 톤 적용.
# 각 테마는 system key(urgent/high/normal/low/vip/hold/overdue) → {bg, border, text} 매핑.
# 사용자 추가 상태(is_system: false, urgent~overdue 외)는 영향 받지 않음.
module CardStatusThemes
  # 키 순서 = 우선순위 (긴급도 / 운영 흐름)
  SYSTEM_KEYS = %w[urgent high normal low vip hold overdue].freeze

  ALL = [
    {
      key: "pastel",
      name: "Pastel",
      desc: "부드러운 톤 (기본)",
      preview_bg: "#FFF1F2", preview_border: "#FECDD3",
      colors: {
        "urgent"  => { bg: "#FFF1F2", border: "#FECDD3", text: "#991B1B" },
        "high"    => { bg: "#FFF7ED", border: "#FED7AA", text: "#9A3412" },
        "normal"  => { bg: "#FAFAFA", border: "#E5E7EB", text: "#374151" },
        "low"     => { bg: "#F0FDF4", border: "#BBF7D0", text: "#14532D" },
        "vip"     => { bg: "#F5F3FF", border: "#DDD6FE", text: "#5B21B6" },
        "hold"    => { bg: "#FEFCE8", border: "#FEF08A", text: "#854D0E" },
        "overdue" => { bg: "#FEE2E2", border: "#FCA5A5", text: "#7F1D1D" }
      }
    },
    {
      key: "vivid",
      name: "Vivid",
      desc: "채도 높은 명확한 구분",
      preview_bg: "#DC2626", preview_border: "#991B1B",
      colors: {
        "urgent"  => { bg: "#DC2626", border: "#991B1B", text: "#FFFFFF" },
        "high"    => { bg: "#EA580C", border: "#9A3412", text: "#FFFFFF" },
        "normal"  => { bg: "#3B82F6", border: "#1E40AF", text: "#FFFFFF" },
        "low"     => { bg: "#16A34A", border: "#14532D", text: "#FFFFFF" },
        "vip"     => { bg: "#9333EA", border: "#5B21B6", text: "#FFFFFF" },
        "hold"    => { bg: "#CA8A04", border: "#854D0E", text: "#FFFFFF" },
        "overdue" => { bg: "#7F1D1D", border: "#450A0A", text: "#FFFFFF" }
      }
    },
    {
      key: "mono",
      name: "Mono",
      desc: "무채색 농도 차이",
      preview_bg: "#1F2937", preview_border: "#374151",
      colors: {
        "urgent"  => { bg: "#1F2937", border: "#111827", text: "#F9FAFB" },
        "high"    => { bg: "#374151", border: "#1F2937", text: "#F9FAFB" },
        "normal"  => { bg: "#9CA3AF", border: "#6B7280", text: "#FFFFFF" },
        "low"     => { bg: "#D1D5DB", border: "#9CA3AF", text: "#1F2937" },
        "vip"     => { bg: "#E5E7EB", border: "#9CA3AF", text: "#111827" },
        "hold"    => { bg: "#F3F4F6", border: "#D1D5DB", text: "#374151" },
        "overdue" => { bg: "#111827", border: "#000000", text: "#F9FAFB" }
      }
    },
    {
      key: "corporate",
      name: "Corporate",
      desc: "AtoZ 브랜드 톤 (Navy/Sky)",
      preview_bg: "#1E3A5F", preview_border: "#00A1E0",
      colors: {
        "urgent"  => { bg: "#D93025", border: "#991B1B", text: "#FFFFFF" },
        "high"    => { bg: "#F4A83A", border: "#B45309", text: "#1E3A5F" },
        "normal"  => { bg: "#1E3A5F", border: "#16325C", text: "#FFFFFF" },
        "low"     => { bg: "#1E8E3E", border: "#14532D", text: "#FFFFFF" },
        "vip"     => { bg: "#00A1E0", border: "#0369A1", text: "#FFFFFF" },
        "hold"    => { bg: "#F3F4F6", border: "#1E3A5F", text: "#16325C" },
        "overdue" => { bg: "#7F1D1D", border: "#450A0A", text: "#FFFFFF" }
      }
    }
  ].freeze

  def self.find(key)
    ALL.find { |t| t[:key] == key.to_s }
  end

  # 적용: 시스템 키만 색상 일괄 변경 (사용자 추가 상태는 보존)
  def self.apply!(theme_key)
    theme = find(theme_key)
    return { ok: false, error: "테마 '#{theme_key}' 없음" } unless theme

    updated = 0
    CardStatus.transaction do
      theme[:colors].each do |key, palette|
        cs = CardStatus.find_by(key: key)
        next unless cs
        cs.update!(bg_color: palette[:bg], border_color: palette[:border], text_color: palette[:text])
        updated += 1
      end
    end
    { ok: true, updated: updated, theme: theme[:name] }
  rescue => e
    { ok: false, error: e.message }
  end
end
