# frozen_string_literal: true

class NotificationsController < ApplicationController
  # ISS-207: 서버사이드 filter + 타입별 카운트
  # params[:filter] = all / unread  (default: all)
  # params[:type]   = all / due_date / status_changed / assigned / system  (default: all)
  def index
    @current_filter = params[:filter].presence_in(%w[all unread]) || "all"
    @current_type   = params[:type].presence_in(%w[all due_date status_changed assigned system]) || "all"

    base = current_user.notifications.includes(:notifiable)
    scoped = base
    scoped = scoped.unread                           if @current_filter == "unread"
    scoped = scoped.where(notification_type: @current_type) if @current_type != "all"
    @notifications = scoped.recent.limit(100)

    # 사이드바 카운트
    @unread_count    = base.unread.count
    @total_count     = base.count
    @type_counts     = base.group(:notification_type).count
    @type_counts_unread = base.unread.group(:notification_type).count
  end

  def read
    notification = current_user.notifications.find(params[:id])
    notification.read!
    redirect_back fallback_location: notifications_path
  end

  def read_all
    # 현재 필터 조건에 맞는 항목만 일괄 읽음 처리
    scope = current_user.notifications.unread
    if params[:type].present? && params[:type] != "all"
      scope = scope.where(notification_type: params[:type])
    end
    count = scope.update_all(read_at: Time.current)
    redirect_back fallback_location: notifications_path, notice: "#{count}건 모두 읽음 처리했습니다."
  end
end
