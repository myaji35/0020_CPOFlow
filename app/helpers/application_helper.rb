module ApplicationHelper
  # Sidebar nav link helper (Redesign Phase 1 — navy shell, 232px)
  def nav_link_to(path, icon:, label:, &block)
    active = current_page?(path) || (path != "/" && request.path.start_with?(path))
    wrapper_class = active ? "active" : ""
    row_class = if active
                  "relative flex items-center gap-3 px-3 py-2 rounded-sm text-[13px] font-medium bg-white/10 text-white"
                else
                  "relative flex items-center gap-3 px-3 py-2 rounded-sm text-[13px] font-medium text-blue-100 hover:bg-white/10 hover:text-white transition-colors"
                end

    content_tag(:div, class: "group #{wrapper_class}".strip) do
      link_to(path, class: row_class) do
        parts = []
        if active
          parts << content_tag(:span, "", class: "absolute -left-2 top-1.5 bottom-1.5 w-[2px] bg-brand-400 rounded-r")
        end
        icon_class = active ? "text-white" : "text-blue-200 group-hover:text-white"
        parts << content_tag(:i, "", class: "#{icon} text-base shrink-0 w-4 text-center #{icon_class} transition-colors")
        parts << content_tag(:span, label,
                              class: "whitespace-nowrap transition-opacity duration-200 truncate",
                              "x-bind:class" => "collapsed ? 'opacity-0 w-0 overflow-hidden' : 'opacity-100'")
        parts << capture(&block) if block
        safe_join(parts)
      end
    end
  end

  # Due date badge (solid bg + white text — SLDS)
  # 2026-04-29: 기본 마감일 D+7 정책 반영 — 임계값 D-3 / D-7 / 그 외.
  def due_badge(order)
    days = order.days_until_due
    return "" unless days

    if days < 0
      content_tag(:span, "OVERDUE #{days.abs}d", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#D93025; color:white")
    elsif days <= 3
      # 빨강 — D-3 이내 (정말 임박)
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#D93025; color:white")
    elsif days <= 7
      # 노랑 — D-4 ~ D-7 (1주 이내, 신규 발주 기본 사이클)
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#F4A83A; color:white")
    else
      # 초록 — 여유 있음
      content_tag(:span, "D-#{days}", class: "text-xs font-semibold px-2 py-0.5 rounded-full", style: "background:#1E8E3E; color:white")
    end
  end

  # Card status badge (solid bg + white text — SLDS)
  def card_status_badge(order)
    cs = order.card_status
    return "".html_safe unless cs
    content_tag(:span, cs.name,
                class: "text-xs font-semibold px-2 py-0.5 rounded-full",
                style: "background:#{cs.text_color}; color:white")
  end

  # 호환 wrapper — 기존 호출 코드가 점진 전환될 때까지 유지
  alias_method :priority_badge, :card_status_badge

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

  # @이름 멘션 파란색 하이라이트 + URL 링크화 + 자동 줄바꿈
  # - "1. ... 2. ... 3. ..." 같이 복수 번호가 한 줄에 붙어 있으면 줄바꿈 강제
  # - "Website:", "Contact:", "Note:" 등 라벨 앞에서도 줄바꿈(1건 이상 탐지 시)
  def highlight_mentions(text)
    return "" if text.blank?
    html = ERB::Util.html_escape(text)

    # 1. 두 개 이상의 번호 매김(1., 2., ...)이 한 줄에 있으면 각 번호 앞에 줄바꿈
    #    앞쪽 공백을 함께 소비하여 시각적 이중 간격 방지
    if html.scan(/(?<=\s)\d{1,2}\.\s/).size >= 2
      html = html.gsub(/\s+(\d{1,2}\.\s)/, "\n\\1")
    end

    # 2. 라벨 패턴(Website:/Contact:/Note:/Email: 등) 앞에 줄바꿈
    #    동일하게 앞 공백을 소비
    labels = %w[Website Contact Note Email Phone Address Tel Fax Manufacturer Brand Distributor]
    label_pattern = /[\s]+((?:#{labels.join("|")}):\s)/
    # 문자열 시작에서는 매칭되지 않도록 개별 카운트는 기존 방식 유지
    label_count_pattern = /(?<=[\s.)])((?:#{labels.join("|")}):\s)/
    if html.scan(label_count_pattern).size >= 2
      html = html.gsub(label_pattern, "\n\\1")
    end

    # 3. URL → 파란 링크 (new tab)
    html = html.gsub(%r{(https?://[^\s<]+)}) do |url|
      safe = ERB::Util.html_escape(url)
      "<a href=\"#{safe}\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"text-blue-600 dark:text-blue-400 underline break-all\">#{safe}</a>"
    end

    # 4. @멘션 → bolder 군청색 (primary navy #1E3A5F)
    #    지시사항 텍스트(회색)와 명확히 구분되도록 더 진하게
    #    한글은 단일 토큰, 영문은 "Title Case 두 단어"까지 허용 (John Doe)
    html = html.gsub(/@([A-Z][a-zA-Z]+(?:[ \t][A-Z][a-zA-Z]+)?|[\w가-힣]+)/) do |match|
      "<span class=\"text-primary dark:text-blue-300 font-bold\" style=\"color:#142844;\">#{ERB::Util.html_escape(match)}</span>"
    end

    # 5. 개행을 <br>로 명시 변환
    html = html.gsub(/\n/, "<br>")

    html.html_safe
  end

  # Task progress (count only)
  def task_progress_bar(order)
    prog = order.task_progress
    return "" if prog[:total].zero?
    content_tag(:div, class: "flex justify-between text-xs text-gray-500") do
      concat content_tag(:span, "Tasks")
      concat content_tag(:span, "#{prog[:done]}/#{prog[:total]}")
    end
  end
end
