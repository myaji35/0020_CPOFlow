class ApplicationController < ActionController::Base
  include Pagy::Backend  # ISS-310: 페이지네이션

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :enforce_active_account
  before_action :set_locale
  before_action :touch_last_seen
  before_action :set_current_user  # ISS-303: 모델 콜백(Auditable concern)에서 current_user 접근용
  before_action :set_sentry_context, if: -> { defined?(Sentry) }

  # ISS-269: Optimistic locking 충돌 시 사용자 친화적 재시도 안내
  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_object_error

  private

  # ISS-303: 모델 콜백(Auditable concern)에서 current_user를 알기 위한 주입.
  def set_current_user
    Current.user = current_user
  end

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

  # 직원 목록 '접속중'/'이용중' 배지용. 1분 throttle(Solid Cache)로 DB 쓰기 부하 최소화.
  # 가장(impersonate) 중에는 실제 admin의 last_seen만 갱신 — 가장 대상 last_seen 부풀림 방지.
  def touch_last_seen
    user = current_real_user
    return unless user
    cache_key = "presence/touched/#{user.id}"
    return if Rails.cache.read(cache_key)
    Rails.cache.write(cache_key, true, expires_in: 1.minute)
    user.update_columns(last_seen_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn "[touch_last_seen] #{e.class}: #{e.message}"
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

  # ── Impersonation (직원 환경 가장) ──────────────────────────────────
  # admin이 직원관리에서 [👁 보기] 클릭 시 해당 직원의 current_user로 앱을 봄.
  # 실제 Devise 세션은 건드리지 않고 세션 키만 오버라이드.
  def current_user
    return @_current_user if defined?(@_current_user)
    @_current_user = if session[:impersonating_user_id].present?
      User.find_by(id: session[:impersonating_user_id]) || super
    else
      super
    end
  end
  helper_method :current_user

  # 가장 중일 때 실제 admin 유저 반환 (배너/권한 체크용)
  def current_real_user
    return @_current_real_user if defined?(@_current_real_user)
    @_current_real_user = if session[:impersonator_id].present?
      User.find_by(id: session[:impersonator_id])
    else
      current_user
    end
  end
  helper_method :current_real_user

  def impersonating?
    session[:impersonating_user_id].present?
  end
  helper_method :impersonating?

  # ── 페르소나 (다중 역할 콤보박스) ─────────────────────────────────
  # kds@ 등 다중 역할 계정용 세션 기반 페르소나 전환. DB role은 불변, session[:persona]만 사용.
  # admin 사용자는 ceo + 4개 권한 페르소나(admin/manager/member/viewer)로 전환 가능.
  # 비-admin은 항상 자기 role.
  # ceo: 시각 표시 전용(타이틀/배지). 권한은 admin과 동일.
  # 권한 페르소나 전환 시 메뉴 가시성/CRUD 버튼은 해당 role 기준 — 단, 백엔드 검증은 실제 사용자 role을 그대로 사용.
  PERSONAS = {
    "ceo"     => { label: "CEO",     icon: "👔", key: "ceo",     role: "admin"   },
    "admin"   => { label: "Admin",   icon: "⚙️", key: "admin",   role: "admin"   },
    "manager" => { label: "Manager", icon: "🛠️", key: "manager", role: "manager" },
    "member"  => { label: "Member",  icon: "👤", key: "member",  role: "member"  },
    "viewer"  => { label: "Viewer",  icon: "👁️", key: "viewer",  role: "viewer"  }
  }.freeze

  def current_persona
    return @_current_persona if defined?(@_current_persona)
    @_current_persona = if current_user&.admin?
      session[:persona].presence&.to_s.in?(PERSONAS.keys) ? session[:persona].to_s : "admin"
    else
      current_user&.role.to_s
    end
  end
  helper_method :current_persona

  # 현재 페르소나가 시뮬레이션하는 role — menu_permission 조회 키.
  # 비-admin은 자기 role 그대로.
  def effective_role
    PERSONAS[current_persona]&.dig(:role) || current_user&.role.to_s
  end
  helper_method :effective_role

  def ceo_mode?
    current_persona == "ceo"
  end
  helper_method :ceo_mode?

  # Branch 데이터 격리: current_user의 branch에 속한 Order만 반환
  # admin은 전체 접근 가능. LAB 샌드박스 Order는 운영 영역에서 자동 제외.
  def scoped_orders
    base = Order.not_archived.not_sandbox
    return base if current_user.admin?
    base.joins(:user).where(users: { branch: current_user.branch })
  end
  helper_method :scoped_orders

  # LAB 전용 — sandbox 포함. admin/manager만 접근.
  def lab_scoped_orders
    base = Order.not_archived
    return base if current_user.admin?
    base.joins(:user).where(users: { branch: current_user.branch })
  end
  helper_method :lab_scoped_orders

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
    # 페르소나 인지: admin이 다른 role 페르소나로 전환하면 그 role의 permission 조회 → 화면이 그 role처럼 보임.
    @_menu_permissions[menu_key.to_s] ||= MenuPermission.find_by(
      role: effective_role, menu_key: menu_key.to_s
    )
  end

  # admin/ceo 페르소나만 무조건 통과. 나머지 페르소나는 menu_permission 따름.
  # 백엔드 강제 가드(require_admin! 등)는 변경 없이 실제 current_user.role을 사용 → 권한 상승 차단.
  def admin_persona?
    current_persona == "admin" || current_persona == "ceo"
  end
  helper_method :admin_persona?

  def can_read?(menu_key)   = admin_persona? || menu_permission_for(menu_key)&.can_read?   || false
  def can_create?(menu_key) = admin_persona? || menu_permission_for(menu_key)&.can_create? || false
  def can_update?(menu_key) = admin_persona? || menu_permission_for(menu_key)&.can_update? || false
  def can_delete?(menu_key) = admin_persona? || menu_permission_for(menu_key)&.can_delete? || false

  helper_method :can_read?, :can_create?, :can_update?, :can_delete?

  def can_access_board?(board)
    return true if admin_persona?
    return true if board&.owner_id == current_user&.id
    return can_read?(:kanban) if board&.is_default?
    can_read?(:kanban)
  end
  helper_method :can_access_board?
end
