class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email    = auth.info.email
      user.name     = auth.info.name
      user.password = Devise.friendly_token[0, 20]
      user.provider = auth.provider
      user.uid      = auth.uid
      # 비밀번호 검증 스킵 (OmniAuth 유저)
      user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    end
  end

  enum :role, { viewer: 0, member: 1, manager: 2, admin: 3 }, default: :member
  enum :branch, { abu_dhabi: "abu_dhabi", seoul: "seoul" }, default: :abu_dhabi

  LOCALES = %w[en ko ar].freeze
  THEMES  = %w[light dark system].freeze

  belongs_to :company, optional: true

  has_many :email_accounts, dependent: :destroy
  has_many :created_orders, class_name: "Order", foreign_key: :user_id, dependent: :nullify
  has_many :assignments, dependent: :destroy
  has_many :assigned_orders, through: :assignments, source: :order
  has_many :tasks, foreign_key: :assignee_id, dependent: :nullify
  has_many :comments, dependent: :nullify
  has_many :activities, dependent: :nullify
  has_many :notifications, dependent: :destroy
  has_one  :employee, dependent: :nullify

  validates :name, presence: true
  validates :locale, inclusion: { in: LOCALES }, allow_blank: true
  validates :theme,  inclusion: { in: THEMES },  allow_blank: true

  # Employee 연결 시 직원 이름 우선 표시, 없으면 User.name
  def display_name
    employee&.name.presence || name.presence || email.split("@").first
  end

  def initials
    display_name.split.map(&:first).first(2).join.upcase
  end

  def linked_to_employee?
    employee.present?
  end

  def admin_or_manager?
    admin? || manager?
  end

  def preferred_locale
    locale.presence || "en"
  end

  def preferred_theme
    theme.presence || "light"
  end

  def dark_mode?
    preferred_theme == "dark"
  end

  # ISS-230: 알림 타입 × 채널 매트릭스
  NOTIFICATION_TYPES = {
    "rfq_new"         => { label: "신규 RFQ 수신", default: true  },
    "order_overdue"   => { label: "주문 연체",       default: true  },
    "order_assigned"  => { label: "담당 배정",       default: true  },
    "visa_expiring"   => { label: "비자 만료 임박", default: true  },
    "ecount_conflict" => { label: "eCount 불일치",  default: false },
    "kpi_weekly"      => { label: "주간 KPI 요약",  default: false }
  }.freeze

  NOTIFICATION_CHANNELS = {
    "in_app" => "앱 알림",
    "email"  => "이메일",
    "slack"  => "Slack",
    "kakao"  => "KakaoTalk"
  }.freeze

  # 특정 타입×채널 조합이 활성화됐는지
  def notify_on?(type, channel)
    prefs = notification_preferences || {}
    row = prefs[type.to_s] || {}
    val = row[channel.to_s]
    return val if val.is_a?(TrueClass) || val.is_a?(FalseClass)
    # 미설정 시 default 반환 (채널은 in_app만 기본 true, 나머지는 false)
    channel.to_s == "in_app" && (NOTIFICATION_TYPES.dig(type.to_s, :default) || false)
  end

  # ISS-229: 저장된 필터 (scope별 쿼리 파라미터 hash)
  # 구조: { "orders" => [ { name: "...", params: { status: "...", period: "..." } }, ... ] }
  def saved_filters_for(scope)
    (saved_filters || {})[scope.to_s] || []
  end

  def add_saved_filter(scope, name, params_hash)
    current = saved_filters || {}
    list = current[scope.to_s] || []
    # 같은 이름 덮어쓰기
    list = list.reject { |f| f["name"] == name }
    list << { "name" => name, "params" => params_hash.to_h, "created_at" => Time.current.iso8601 }
    list = list.last(10)  # 최대 10개
    current[scope.to_s] = list
    update!(saved_filters: current)
  end

  def remove_saved_filter(scope, name)
    current = saved_filters || {}
    list = (current[scope.to_s] || []).reject { |f| f["name"] == name }
    current[scope.to_s] = list
    update!(saved_filters: current)
  end

  # ── 온보딩 헬퍼 (ISS-240) ──────────────────────────────────

  # Gmail(email_account) 연결 여부
  def gmail_connected?
    email_accounts.exists?
  end

  # 본인이 생성한 발주 1건 이상
  def has_created_order?
    created_orders.exists?
  end

  # 본인이 배정받은 order 1건 이상
  def has_assignment?
    assignments.exists?
  end

  # 3단계 모두 완료 시 온보딩 완료
  def onboarded?
    gmail_connected? && has_created_order? && has_assignment?
  end

  # 각 단계별 완료 여부 반환 (뷰 체크리스트용)
  def onboarding_steps
    [
      { key: :gmail,      done: gmail_connected?,   label: "Gmail 연결",      cta_label: "Gmail 연결하기",    cta_path: nil },
      { key: :order,      done: has_created_order?, label: "첫 발주 만들기",  cta_label: "발주 만들기",        cta_path: nil },
      { key: :assignment, done: has_assignment?,    label: "담당자 배정 받기", cta_label: "칸반에서 배정받기", cta_path: nil }
    ]
  end
end
