class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_locale

  private

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
