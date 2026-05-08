class User < ApplicationRecord
  # AUDIT-009: :registerable 제거 — 외부 회원가입 차단 (admin 초대 + Google OAuth 신규 가입만 허용)
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  def self.from_omniauth(auth)
    user = where(provider: auth.provider, uid: auth.uid).first_or_create do |u|
      u.email    = auth.info.email
      u.name     = auth.info.name
      u.password = Devise.friendly_token[0, 20]
      u.provider = auth.provider
      u.uid      = auth.uid
      # ISS-268: 이메일 도메인 기반 branch 자동 분기 — 모호 시 enum default(:abu_dhabi) 유지
      #   seoul 단서: .kr TLD, seoul/korea 서브도메인, 한국어 이름 힌트
      #   그 외: default(:abu_dhabi) — admin이 필요 시 수동 재배정
      inferred_branch = infer_branch_from_email(auth.info.email)
      u.branch = inferred_branch if inferred_branch
      # 비밀번호 검증 스킵 (OmniAuth 유저)
      u.skip_confirmation! if u.respond_to?(:skip_confirmation!)

      # AtoZ 직원만 사용:
      # 로그인 이메일 == Employee 등록 이메일 → admin이 직원으로 등록한 사실 자체가 사용 자격 인증
      # 매칭 성공: active=true + role=member (manager/admin 승격은 admin이 별도 수행)
      # 매칭 실패: active=false (pending 안내 페이지)
      matched = Employee.find_by("LOWER(email) = ?", auth.info.email.to_s.downcase)
      if matched
        u.active = true
        u.role   = :member
      else
        u.active = false
      end
    end

    # 신규 사용자 + 매칭되는 Employee 있으면 양방향 연결 (Employee.user_id 채우기)
    if user.persisted? && user.employee.nil?
      matched_employee = Employee.find_by("LOWER(email) = ?", auth.info.email.to_s.downcase)
      matched_employee&.update_column(:user_id, user.id)
    end
    user
  end

  # ISS-268: 이메일 도메인 분석 → 추정 branch 반환 (확신 없으면 nil)
  def self.infer_branch_from_email(email)
    return nil if email.blank?
    domain = email.to_s.split("@").last.to_s.downcase
    return :seoul if domain.end_with?(".kr") || domain.include?("seoul") || domain.include?("korea")
    return :abu_dhabi if domain.include?("abudhabi") || domain.include?("uae") || domain.end_with?(".ae")
    nil
  end

  # ISS-259: 신규 가입자 default role을 :viewer로 하향 (외부인 가입 시 발주 데이터 노출 차단).
  # 기존 저장된 사용자 role은 변경하지 않음 — admin이 수동 승격해야 member 이상 권한 부여.
  enum :role, { viewer: 0, member: 1, manager: 2, admin: 3 }, default: :viewer
  enum :branch, { abu_dhabi: "abu_dhabi", seoul: "seoul" }, default: :abu_dhabi

  # AtoZ 직원만 사용 가능 — Employee 매칭 안 된 사용자는 active=false (모든 페이지 차단, 안내만 표시)
  # pending? = 가입은 했지만 직원 등록 대기 중
  def pending? = !active?

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

  # ISS-296: 퇴사자 계정 잠금 — Employee.active=false 또는 termination_date 경과 시 로그인 차단
  def active_for_authentication?
    super && active
  end

  def inactive_message
    active ? super : :account_deactivated
  end

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

  # ── Presence (접속/이용 상태) ────────────────────────────────
  # ApplicationController#touch_last_seen이 1분 throttle로 last_seen_at 갱신.
  ONLINE_WINDOW         = 5.minutes
  RECENTLY_ACTIVE_WINDOW = 30.minutes

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  end

  def recently_active?
    last_seen_at.present? && last_seen_at > RECENTLY_ACTIVE_WINDOW.ago
  end

  # 표시용 문자열 키: "online" / "active" / "offline"
  def presence_state
    return "online"  if online?
    return "active"  if recently_active?
    "offline"
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
