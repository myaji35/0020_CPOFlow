class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_locale

  private

  def set_locale
    if user_signed_in?
      I18n.locale = current_user.preferred_locale.to_sym
    else
      I18n.locale = :en
    end
  end

  def require_manager!
    unless current_user&.admin_or_manager?
      redirect_to root_path, alert: "Access denied."
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
end
