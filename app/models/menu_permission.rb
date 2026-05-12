class MenuPermission < ApplicationRecord
  ROLES     = %w[viewer member manager admin].freeze
  # ISS-381: contact_persons/calendar/team/reports 추가 — 사이드바 노출되지만 권한 설정 화면에서 누락 갭 해소.
  MENU_KEYS = %w[orders clients suppliers projects employees org_chart inbox kanban admin
                 contact_persons calendar team reports].freeze

  MENU_LABELS = {
    "orders"          => "발주 관리",
    "clients"         => "발주처 관리",
    "suppliers"       => "거래처 관리",
    "projects"        => "현장 관리",
    "employees"       => "직원 관리",
    "org_chart"       => "조직도",
    "inbox"           => "인박스",
    "kanban"          => "칸반 보드",
    "admin"           => "관리자 메뉴",
    "contact_persons" => "외부 담당자",
    "calendar"        => "캘린더",
    "team"            => "팀 관리",
    "reports"         => "경영 리포트"
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
