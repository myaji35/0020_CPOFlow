module ReportsHelper
  def delta_badge(curr, prev_val)
    return "".html_safe if prev_val.nil? || prev_val == 0

    pct = ((curr - prev_val).to_f / prev_val * 100).round(1)
    arrow = pct >= 0 ? "\u25B2" : "\u25BC"
    color = pct >= 0 ? "text-green-600 dark:text-green-400" : "text-red-500 dark:text-red-400"

    tag.span("#{arrow} #{pct.abs}%", class: "text-xs #{color} font-medium ml-1")
  end
end
