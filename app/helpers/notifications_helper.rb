# frozen_string_literal: true

module NotificationsHelper
  # 사용자의 카테고리별 총 카운트 + 미읽음 카운트를 반환
  # 반환: { category => { total: N, unread: N } }
  # 단, raw notification_type을 category로 매핑해서 합산
  def notification_categories_with_count(user)
    base = user.notifications
    raw_totals = base.group(:notification_type).count
    raw_unread = base.unread.group(:notification_type).count

    result = Hash.new { |h, k| h[k] = { total: 0, unread: 0 } }
    raw_totals.each do |type, cnt|
      cat = Notification.new(notification_type: type).category
      result[cat][:total] += cnt
    end
    raw_unread.each do |type, cnt|
      cat = Notification.new(notification_type: type).category
      result[cat][:unread] += cnt
    end
    result
  end

  # 카테고리에 해당하는 notification_type 목록 반환 (SQL WHERE 조건용)
  # nil → 해당 카테고리에 매핑되는 type 배열
  def types_for_category(category)
    return nil if category == "all"

    Notification::CATEGORY_MAP.filter_map do |pattern, cat|
      next unless cat == category
      pattern  # Regexp 또는 String — 컨트롤러에서 처리
    end
  end
end
