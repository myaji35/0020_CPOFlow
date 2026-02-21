class MenuPermission < ApplicationRecord
  ROLES     = %w[viewer member manager admin].freeze
  MENU_KEYS = %w[orders clients suppliers projects employees org_chart inbox kanban admin].freeze

  MENU_LABELS = {
    "orders"    => "발주 관리",
    "clients"   => "발주처 관리",
    "suppliers" => "거래처 관리",
    "projects"  => "현장 관리",
    "employees" => "직원 관리",
    "org_chart" => "조직도",
    "inbox"     => "인박스",
    "kanban"    => "칸반 보드",
    "admin"     => "관리자 메뉴"
  }.freeze

  DEFAULT_PERMISSIONS = {
    "viewer"  => { can_read: true,  can_create: false, can_update: false, can_delete: false },
    "member"  => { can_read: true,  can_create: true,  can_update: true,  can_delete: false },
    "manager" => { can_read: true,  can_create: true,  can_update: true,  can_delete: true  },
    "admin"   => { can_read: true,  can_create: true,  can_update: true,  can_delete: true  }
  }.freeze

  validates :role,     inclusion: { in: ROLES }
  validates :menu_key, inclusion: { in: MENU_KEYS }
  validates :menu_key, uniqueness: { scope: :role }

  scope :for_role, ->(role) { where(role: role) }

  def menu_label = MENU_LABELS[menu_key] || menu_key
end
