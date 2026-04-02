module ApplicationHelper
  # Sidebar nav link helper
  def nav_link_to(path, icon:, label:, &block)
    active = current_page?(path) || request.path.start_with?(path) && path != "/"
    base_class = "flex items-center gap-3 px-3 py-2.5 mx-1 rounded-lg text-sm font-medium transition-colors overflow-hidden"
    active_class = "#{base_class} bg-white/20 text-white"
    inactive_class = "#{base_class} text-blue-100 hover:bg-white/10 hover:text-white"

    content_tag(:div, class: active ? active_class : inactive_class) do
      concat link_to(path, class: "flex items-center gap-3 flex-1 overflow-hidden") {
        concat content_tag(:i, "", class: "#{icon} text-xl shrink-0 w-5 text-center")
        concat content_tag(:span, label, class: "whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity duration-200 truncate")
        capture(&block) if block
      }
    end
  end

  # Due date badge (solid bg + white text — SLDS)
  def due_badge(order)
    days = order.days_until_due
    return "" unless days

    if days < 0
      content_tag(:span, "OVERDUE #{days.abs}d", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#D93025; color:white")
    elsif days <= 7
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#D93025; color:white")
    elsif days <= 14
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#F4A83A; color:white")
    else
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#1E8E3E; color:white")
    end
  end

  # Priority badge (solid bg + white text — SLDS)
  PRIORITY_COLORS = {
    "low"    => "#6b7280",
    "medium" => "#00A1E0",
    "high"   => "#F4A83A",
    "urgent" => "#D93025"
  }.freeze

  def priority_badge(order)
    bg = PRIORITY_COLORS[order.priority] || "#6b7280"
    content_tag(:span, order.priority.upcase, class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#{bg}; color:white")
  end

  # Status badge (solid bg + white text — SLDS)
  STATUS_COLORS = {
    "new_rfq"        => "#6b7280",
    "make_quo"       => "#00A1E0",
    "pending_po"     => "#7c3aed",
    "new_po"         => "#4f46e5",
    "delivery_items" => "#d97706",
    "problem"        => "#D93025",
    "get_grn"        => "#1E8E3E",
    "give_up"        => "#9ca3af",
    "done"           => "#374151"
  }.freeze

  def status_badge(order)
    label = Order::STATUS_LABELS[order.status] || order.status.humanize
    bg = STATUS_COLORS[order.status] || "#6b7280"
    content_tag(:span, label, class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#{bg}; color:white")
  end

  # Due date color class (for inline use in views)
  def due_date_color_class(due_date)
    return "text-gray-500 dark:text-gray-400" if due_date.nil?
    days = (due_date.to_date - Date.today).to_i
    if days < 0         then "text-red-700 dark:text-red-400 font-semibold"
    elsif days <= 7     then "text-red-600 dark:text-red-400"
    elsif days <= 14    then "text-orange-500 dark:text-orange-400"
    else                     "text-green-600 dark:text-green-400"
    end
  end

  # @이름 멘션 파란색 하이라이트 (FR-08)
  def highlight_mentions(text)
    return "" if text.blank?
    html = ERB::Util.html_escape(text)
    html.gsub(/@([\w가-힣]+(?:\s[\w가-힣]+)?)/) do |match|
      "<span class=\"text-blue-600 dark:text-blue-400 font-medium\">#{ERB::Util.html_escape(match)}</span>"
    end.html_safe
  end

  # Task progress bar
  def task_progress_bar(order)
    prog = order.task_progress
    return "" if prog[:total].zero?
    pct = (prog[:done].to_f / prog[:total] * 100).round
    content_tag(:div, class: "w-full") do
      concat content_tag(:div, class: "flex justify-between text-xs text-gray-500 mb-1") {
        concat content_tag(:span, "Tasks")
        concat content_tag(:span, "#{prog[:done]}/#{prog[:total]}")
      }
      concat content_tag(:div, class: "w-full bg-gray-200 rounded-full h-1.5") {
        content_tag(:div, "", class: "bg-accent h-1.5 rounded-full", style: "width: #{pct}%")
      }
    end
  end
end
