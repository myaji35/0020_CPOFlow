module CalendarHelper
  # 주문 상태별 셀 배경색 (연체/긴급/진행/완료)
  def calendar_order_color(order, today = Date.today)
    if order.done? || order.get_grn?
      "bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-400"
    elsif order.due_date < today && !order.done?
      "bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400"
    elsif order.due_date <= today + 7
      "bg-orange-50 dark:bg-orange-900/20 text-orange-700 dark:text-orange-400"
    else
      "bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-400"
    end
  end

  # 상태별 도트 색상 (solid)
  def calendar_dot_color(order, today = Date.today)
    if order.done? || order.get_grn?
      "bg-green-500"
    elsif order.due_date < today && !order.done?
      "bg-red-500"
    elsif order.due_date <= today + 7
      "bg-orange-500"
    else
      "bg-blue-500"
    end
  end
end
