# frozen_string_literal: true

# 칸반 범례 컬러 테마 — 한 번 클릭으로 전체 카드 상태에 일관된 톤 적용.
# 각 테마는 system key(urgent/high/normal/low/vip/hold/overdue) → {bg, border, text} 매핑.
# 사용자 추가 상태(is_system: false, urgent~overdue 외)는 영향 받지 않음.
module CardStatusThemes
  # 키 순서 = 우선순위 (긴급도 / 운영 흐름)
  SYSTEM_KEYS = %w[urgent high normal low vip hold overdue].freeze

  # 4단계 농도 테마 — 검정 글씨(#111827) 고정, 배경색만 Pastel→Vivid 방향 농도 변화.
  # 명도(L) 기준 ≥60 유지로 검정 글씨 대비 4.5:1 이상 (WCAG AA 통과).
  # 각 테마의 7개 상태는 같은 농도 레벨에서 Tailwind 색상 변형.
  BLACK_TEXT = "#111827" # gray-900 — 모든 테마 공통 검정 글씨

  ALL = [
    {
      key: "level1",
      name: "L1 · Soft",
      desc: "가장 연한 파스텔 (50/100)",
      preview_bg: "#FEF2F2", preview_border: "#FECACA",
      colors: {
        "urgent"  => { bg: "#FEF2F2", border: "#FECACA", text: BLACK_TEXT }, # red-50/200
        "high"    => { bg: "#FFF7ED", border: "#FED7AA", text: BLACK_TEXT }, # orange-50/200
        "normal"  => { bg: "#EFF6FF", border: "#BFDBFE", text: BLACK_TEXT }, # blue-50/200
        "low"     => { bg: "#F0FDF4", border: "#BBF7D0", text: BLACK_TEXT }, # green-50/200
        "vip"     => { bg: "#F5F3FF", border: "#DDD6FE", text: BLACK_TEXT }, # violet-50/200
        "hold"    => { bg: "#FEFCE8", border: "#FEF08A", text: BLACK_TEXT }, # yellow-50/200
        "overdue" => { bg: "#FEE2E2", border: "#FCA5A5", text: BLACK_TEXT }  # red-100/300
      }
    },
    {
      key: "level2",
      name: "L2 · Light",
      desc: "연한 중간 톤 (200)",
      preview_bg: "#FECACA", preview_border: "#FCA5A5",
      colors: {
        "urgent"  => { bg: "#FECACA", border: "#FCA5A5", text: BLACK_TEXT }, # red-200
        "high"    => { bg: "#FED7AA", border: "#FDBA74", text: BLACK_TEXT }, # orange-200
        "normal"  => { bg: "#BFDBFE", border: "#93C5FD", text: BLACK_TEXT }, # blue-200
        "low"     => { bg: "#BBF7D0", border: "#86EFAC", text: BLACK_TEXT }, # green-200
        "vip"     => { bg: "#DDD6FE", border: "#C4B5FD", text: BLACK_TEXT }, # violet-200
        "hold"    => { bg: "#FEF08A", border: "#FDE047", text: BLACK_TEXT }, # yellow-200
        "overdue" => { bg: "#FCA5A5", border: "#F87171", text: BLACK_TEXT }  # red-300
      }
    },
    {
      key: "level3",
      name: "L3 · Medium",
      desc: "중간 채도 (300)",
      preview_bg: "#FCA5A5", preview_border: "#F87171",
      colors: {
        "urgent"  => { bg: "#FCA5A5", border: "#F87171", text: BLACK_TEXT }, # red-300
        "high"    => { bg: "#FDBA74", border: "#FB923C", text: BLACK_TEXT }, # orange-300
        "normal"  => { bg: "#93C5FD", border: "#60A5FA", text: BLACK_TEXT }, # blue-300
        "low"     => { bg: "#86EFAC", border: "#4ADE80", text: BLACK_TEXT }, # green-300
        "vip"     => { bg: "#C4B5FD", border: "#A78BFA", text: BLACK_TEXT }, # violet-300
        "hold"    => { bg: "#FDE047", border: "#FACC15", text: BLACK_TEXT }, # yellow-300
        "overdue" => { bg: "#F87171", border: "#EF4444", text: BLACK_TEXT }  # red-400
      }
    },
    {
      key: "level4",
      name: "L4 · Strong",
      desc: "가장 진한 파스텔 (400, 글씨 가독 한계)",
      preview_bg: "#F87171", preview_border: "#EF4444",
      colors: {
        "urgent"  => { bg: "#F87171", border: "#EF4444", text: BLACK_TEXT }, # red-400
        "high"    => { bg: "#FB923C", border: "#F97316", text: BLACK_TEXT }, # orange-400
        "normal"  => { bg: "#60A5FA", border: "#3B82F6", text: BLACK_TEXT }, # blue-400
        "low"     => { bg: "#4ADE80", border: "#22C55E", text: BLACK_TEXT }, # green-400
        "vip"     => { bg: "#A78BFA", border: "#8B5CF6", text: BLACK_TEXT }, # violet-400
        "hold"    => { bg: "#FACC15", border: "#EAB308", text: BLACK_TEXT }, # yellow-400
        "overdue" => { bg: "#EF4444", border: "#DC2626", text: BLACK_TEXT }  # red-500 (경계)
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
