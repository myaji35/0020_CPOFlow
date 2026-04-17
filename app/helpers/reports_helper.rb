module ReportsHelper
  # 증감률 배지. label: 비교 대상 라벨 ("전기" 기본, "YoY"/"전월" 등)
  # lower_is_better: true면 감소를 초록색으로 표시 (예: 지연율)
  def delta_badge(curr, prev_val, label: nil, lower_is_better: false)
    return "".html_safe if prev_val.nil? || prev_val == 0

    pct = ((curr - prev_val).to_f / prev_val * 100).round(1)
    arrow = pct >= 0 ? "\u25B2" : "\u25BC"
    good  = lower_is_better ? (pct <= 0) : (pct >= 0)
    color = good ? "text-green-600 dark:text-green-400" : "text-red-500 dark:text-red-400"
    text  = label ? "#{arrow} #{pct.abs}% vs #{label}" : "#{arrow} #{pct.abs}%"

    tag.span(text, class: "text-xs #{color} font-medium ml-1")
  end
end
