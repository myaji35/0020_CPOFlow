# frozen_string_literal: true

class NotificationsController < ApplicationController
  # AUDIT-004: 카테고리 기반 필터 (실 DB free-text type → category 매핑)
  # params[:filter]   = all / unread  (default: all)
  # params[:category] = all / due_date / status_changed / assigned / system /
  #                     visa / contract / overdue_escalation /
  #                     ecount_slip_failed / oauth_signup / mentioned
  VALID_CATEGORIES = (["all"] + Notification::TYPES).freeze

  def index
    @current_filter   = params[:filter].presence_in(%w[all unread]) || "all"
    @current_category = params[:category].presence || "all"
    @current_category = "all" unless Notification::CATEGORY_LABELS.key?(@current_category)

    base = current_user.notifications.includes(:notifiable)
    scoped = base
    scoped = scoped.unread if @current_filter == "unread"

    if @current_category != "all"
      scoped = apply_category_filter(scoped, @current_category)
    end

    @notifications = scoped.recent.limit(100)

    # 카운트: raw type → category로 집계
    @unread_count   = base.unread.count
    @total_count    = base.count
    @category_counts        = aggregate_by_category(base.group(:notification_type).count)
    @category_counts_unread = aggregate_by_category(base.unread.group(:notification_type).count)

    # 레거시 호환 (뷰에서 @current_type 참조 대비)
    @current_type = @current_category
    @type_counts        = @category_counts
    @type_counts_unread = @category_counts_unread
  end

  def read
    notification = current_user.notifications.find(params[:id])
    notification.read!
    respond_to do |format|
      format.json { head :ok }
      format.html { redirect_back fallback_location: notifications_path }
    end
  end

  # ISS-353 Phase 1: 멘션 [✓ 확인] 명시 클릭
  # 본인 소유 notification만 대상 — current_user.notifications scope로 자동 권한 검증
  # 다른 사용자 id 추측 시 ActiveRecord::RecordNotFound (404)
  def acknowledge
    notification = current_user.notifications.find(params[:id])
    notification.acknowledge!(viewer: current_user)
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.json         { head :ok }
      format.html         { redirect_back fallback_location: notifications_path }
    end
  end

  # ISS-353 Phase 1: 뷰포트 5초 연속 노출 시 자동 viewed_at 기록
  # duration은 0..3600 클램프 (안티 게이밍: 비현실적 long-tail 차단)
  def view
    notification = current_user.notifications.find(params[:id])
    duration = params[:duration].to_i.clamp(0, 3600)
    notification.mark_viewed!(duration_sec: duration)
    head :ok
  end

  def read_all
    scope = current_user.notifications.unread
    if params[:category].present? && params[:category] != "all"
      scope = apply_category_filter(scope, params[:category])
    elsif params[:type].present? && params[:type] != "all"
      # 레거시 호환
      scope = scope.where(notification_type: params[:type])
    end
    count = scope.update_all(read_at: Time.current)
    redirect_back fallback_location: notifications_path, notice: "#{count}건 모두 읽음 처리했습니다."
  end

  private

  # category 값을 받아 해당 notification_type 들을 SQL WHERE로 변환
  def apply_category_filter(scope, category)
    matching_types = raw_types_for_category(category)
    return scope if matching_types.empty?

    # Regexp 패턴은 SQLite GLOB/LIKE로, String은 = 조건으로 처리
    string_types   = matching_types.select { |p| p.is_a?(String) }
    regexp_types   = matching_types.select { |p| p.is_a?(Regexp) }

    # 패턴에 맞는 실제 type 값을 미리 조회 (배치 최적화)
    all_types = scope.distinct.pluck(:notification_type).compact
    matched   = all_types.select do |t|
      string_types.include?(t) ||
        regexp_types.any? { |r| t.match?(r) }
    end

    # 해당 카테고리에 매핑 안 되는 nil도 system이면 포함
    if category == "system"
      matched += all_types.select do |t|
        Notification.new(notification_type: t).category == "system"
      end
      matched << nil  # nil → system 백필 전 임시 포함
    end

    scope.where(notification_type: matched.uniq)
  end

  # raw_counts { type => cnt } → { category => cnt }
  def aggregate_by_category(raw_counts)
    result = Hash.new(0)
    raw_counts.each do |type, cnt|
      cat = Notification.new(notification_type: type).category
      result[cat] += cnt
    end
    result
  end

  # Notification::CATEGORY_MAP에서 해당 category에 매핑되는 패턴 목록 반환
  def raw_types_for_category(category)
    Notification::CATEGORY_MAP.filter_map { |pattern, cat| cat == category ? pattern : nil }
  end
end
