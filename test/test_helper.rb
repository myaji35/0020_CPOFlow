require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  # fixtures :all  # fixture 없이 DB 직접 사용

  # ISS-304/ISS-380: enforce_menu_permission!이 통과하려면 (role, menu_key) 레코드 필요.
  # 운영 환경은 admin UI seed가 처리하지만 테스트 DB는 비어있어 컨트롤러 가드가 차단된다.
  # MenuPermission::DEFAULT_PERMISSIONS 기준으로 모든 (role × menu_key) 조합을 미리 채워둔다.
  def self.seed_menu_permissions!
    MenuPermission::ROLES.each do |role|
      defaults = MenuPermission::DEFAULT_PERMISSIONS[role]
      MenuPermission::MENU_KEYS.each do |menu_key|
        MenuPermission.find_or_create_by(role: role, menu_key: menu_key) do |p|
          p.can_read   = defaults[:can_read]
          p.can_create = defaults[:can_create]
          p.can_update = defaults[:can_update]
          p.can_delete = defaults[:can_delete]
        end
      end
    end
  end
  seed_menu_permissions!
end
