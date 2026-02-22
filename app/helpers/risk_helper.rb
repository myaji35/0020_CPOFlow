# frozen_string_literal: true

module RiskHelper
  RISK_CSS = {
    "critical" => "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400",
    "high"     => "bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400",
    "medium"   => "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400",
    "low"      => "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400",
    "none"     => "bg-gray-100 text-gray-500 dark:bg-gray-700 dark:text-gray-400"
  }.freeze

  RISK_ICON = {
    "critical" => "●",
    "high"     => "●",
    "medium"   => "●",
    "low"      => "●",
    "none"     => ""
  }.freeze

  RISK_LABEL = {
    "critical" => "위험",
    "high"     => "주의",
    "medium"   => "경고",
    "low"      => "정상",
    "none"     => "-"
  }.freeze

  RISK_DOT_CSS = {
    "critical" => "text-red-500",
    "high"     => "text-orange-400",
    "medium"   => "text-yellow-400",
    "low"      => "text-green-500",
    "none"     => "text-gray-300"
  }.freeze

  def risk_badge(order)
    level = order.risk_level.presence || "none"
    css   = RISK_CSS[level]
    dot   = RISK_DOT_CSS[level]
    label = RISK_LABEL[level]
    return "".html_safe if level == "none"

    content_tag(:span, class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium #{css}") do
      content_tag(:span, "●", class: dot) + label
    end
  end

  def risk_dot(order)
    level = order.risk_level.presence || "none"
    return "".html_safe if level == "none"
    content_tag(:span, "●", class: "text-xs #{RISK_DOT_CSS[level]}", title: RISK_LABEL[level])
  end
end
