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

  # Due date badge
  def due_badge(order)
    days = order.days_until_due
    return "" unless days

    if days < 0
      content_tag(:span, "OVERDUE #{days.abs}d", class: "text-xs font-semibold bg-red-100 text-red-700 px-2 py-0.5 rounded-full")
    elsif days <= 7
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold bg-red-100 text-red-700 px-2 py-0.5 rounded-full")
    elsif days <= 14
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold bg-orange-100 text-orange-700 px-2 py-0.5 rounded-full")
    else
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold bg-green-100 text-green-700 px-2 py-0.5 rounded-full")
    end
  end

  # Priority badge
  def priority_badge(order)
    colors = {
      "low"    => "bg-gray-100 text-gray-600",
      "medium" => "bg-blue-100 text-blue-700",
      "high"   => "bg-orange-100 text-orange-700",
      "urgent" => "bg-red-100 text-red-700"
    }
    klass = colors[order.priority] || "bg-gray-100 text-gray-600"
    content_tag(:span, order.priority.upcase, class: "text-xs font-semibold #{klass} px-2 py-0.5 rounded-full")
  end

  # Status badge
  def status_badge(order)
    colors = {
      "inbox"     => "bg-gray-100 text-gray-700",
      "reviewing" => "bg-blue-100 text-blue-700",
      "quoted"    => "bg-purple-100 text-purple-700",
      "confirmed" => "bg-indigo-100 text-indigo-700",
      "procuring" => "bg-yellow-100 text-yellow-700",
      "qa"        => "bg-orange-100 text-orange-700",
      "delivered" => "bg-green-100 text-green-700"
    }
    label = Order::STATUS_LABELS[order.status] || order.status.humanize
    klass = colors[order.status] || "bg-gray-100 text-gray-700"
    content_tag(:span, label, class: "text-xs font-semibold #{klass} px-2 py-0.5 rounded-full")
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
