class ApplicationController < ActionController::Base
  include Pagy::Backend  # ISS-310: 페이지네이션

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :enforce_active_account
  before_action :set_locale
  before_action :set_sentry_context, if: -> { defined?(Sentry) }

  # ISS-269: Optimistic locking 충돌 시 사용자 친화적 재시도 안내
  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_object_error

  private

  # AtoZ 직원만 사용: Employee 매칭 안 된 사용자는 /pending_approval 안내 페이지만 보이게 차단.
  # 통과 조건: current_user.active? (Employee 매칭 시 자동 활성화) 또는 허용 라우트
  def enforce_active_account
    return unless current_user
    return if current_user.active?
    # 차단 예외 라우트: 안내 페이지, 로그아웃, 법적 페이지
    allowed_paths = [ pending_approval_path, destroy_user_session_path, privacy_policy_path, terms_of_service_path ]
    return if allowed_paths.include?(request.path)
    return if request.path.start_with?("/users/sign_out", "/rails/")
    redirect_to pending_approval_path
  end

  def set_sentry_context
    return unless current_user
    Sentry.set_user(
      id: current_user.id,
      email: current_user.email,
      role: current_user.role
    )
    Sentry.set_tags(
      branch: current_user.try(:branch).to_s,
      role: current_user.role
    )
  end

  def handle_stale_object_error(exception)
    Rails.logger.warn "[ISS-269] StaleObjectError #{exception.record&.class}##{exception.record&.id} by user=#{current_user&.id}"
    msg = "다른 사용자가 먼저 수정했습니다. 화면을 새로고침한 뒤 다시 시도하세요."
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.append("flash-container", %(<div class="flash-error">#{msg}</div>).html_safe), status: :conflict }
      format.json         { render json: { error: msg, stale: true }, status: :conflict }
      format.html         { redirect_back fallback_location: root_path, alert: msg }
    end
  end

  # ISS-271: Gmail 토큰 만료/연결 끊김 감지 — 전역 배너용
  # 반환값: { needs_action: bool, disconnected_count: int, reauth_count: int, total: int }
  def gmail_connection_health
    return @_gmail_connection_health if defined?(@_gmail_connection_health)
    return @_gmail_connection_health = { needs_action: false } unless user_signed_in?
    accounts = current_user.email_accounts.to_a
    return @_gmail_connection_health = { needs_action: false, total: 0 } if accounts.empty?
    disconnected = accounts.count { |a| !a.connected? }
    reauth       = accounts.count { |a| a.connected? && a.gmail_refresh_token.blank? }
    needs_action = disconnected.positive? || reauth.positive?
    @_gmail_connection_health = {
      needs_action: needs_action,
      disconnected_count: disconnected,
      reauth_count: reauth,
      total: accounts.size,
      primary_account: accounts.first
    }
  end
  helper_method :gmail_connection_health

  # Branch 데이터 격리: current_user의 branch에 속한 Order만 반환
  # admin은 전체 접근 가능
  def scoped_orders
    base = Order.not_archived
    return base if current_user.admin?
    base.joins(:user).where(users: { branch: current_user.branch })
  end
  helper_method :scoped_orders

  def set_locale
    if user_signed_in?
      I18n.locale = current_user.preferred_locale.to_sym
    else
      # 비로그인 상태(로그인 페이지, Devise 메시지): Accept-Language 헤더 → :ko 기본값
      accepted = request.env["HTTP_ACCEPT_LANGUAGE"]&.scan(/^[a-z]{2}/)&.first&.to_sym
      I18n.locale = (accepted == :en) ? :en : :ko
    end
  end

  def require_manager!
    unless current_user&.admin_or_manager?
      redirect_to root_path, alert: "Access denied."
    end
  end

  # viewer를 제외한 member 이상만 허용 (AI API 호출 비용 방지)
  def require_member!
    return if current_user&.admin? || current_user&.manager? || current_user&.member?
    respond_to do |format|
      format.html { redirect_to root_path, alert: "이 작업은 멤버 이상만 사용할 수 있습니다." }
      format.json { render json: { error: "Insufficient role" }, status: :forbidden }
    end
  end

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "관리자만 접근 가능합니다."
    end
  end

  def menu_permission_for(menu_key)
    return nil unless user_signed_in?
    @_menu_permissions ||= {}
    @_menu_permissions[menu_key.to_s] ||= MenuPermission.find_by(
      role: current_user.role, menu_key: menu_key.to_s
    )
  end

  def can_read?(menu_key)   = current_user&.admin? || menu_permission_for(menu_key)&.can_read?   || false
  def can_create?(menu_key) = current_user&.admin? || menu_permission_for(menu_key)&.can_create? || false
  def can_update?(menu_key) = current_user&.admin? || menu_permission_for(menu_key)&.can_update? || false
  def can_delete?(menu_key) = current_user&.admin? || menu_permission_for(menu_key)&.can_delete? || false

  helper_method :can_read?, :can_create?, :can_update?, :can_delete?

  def can_access_board?(board)
    return true if current_user&.admin?
    return true if board&.owner_id == current_user&.id
    return can_read?(:kanban) if board&.is_default?
    can_read?(:kanban)
  end
  helper_method :can_access_board?
end
