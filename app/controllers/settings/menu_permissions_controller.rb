module Settings
  class MenuPermissionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      @role = params[:role].presence_in(MenuPermission::ROLES) || "member"
      @permissions = MenuPermission::MENU_KEYS.map do |key|
        MenuPermission.find_or_initialize_by(role: @role, menu_key: key)
      end
    end

    def update_all
      role = params[:role].presence_in(MenuPermission::ROLES)
      return redirect_to settings_menu_permissions_path, alert: "올바르지 않은 역할입니다." unless role

      MenuPermission::MENU_KEYS.each do |key|
        perm = MenuPermission.find_or_create_by(role: role, menu_key: key)
        perm_params = params.dig(:permissions, key) || {}
        perm.update(
          can_read:   perm_params[:can_read]   == "1",
          can_create: perm_params[:can_create] == "1",
          can_update: perm_params[:can_update] == "1",
          can_delete: perm_params[:can_delete] == "1"
        )
      end

      redirect_to settings_menu_permissions_path(role: role), notice: "권한이 저장되었습니다."
    end

    private

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근할 수 있습니다." unless current_user.admin?
    end
  end
end
