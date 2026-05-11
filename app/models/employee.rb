class Employee < ApplicationRecord
  include DocumentAttachable

  # 직원 프로필 사진 (헤더 80x80 원형 표시)
  has_one_attached :avatar
  validate :validate_avatar_safety

  AVATAR_ALLOWED_MIMES = %w[image/jpeg image/pjpeg image/png image/webp image/heic image/heif].freeze
  AVATAR_MAX_SIZE      = 3.megabytes

  belongs_to :user,       optional: true
  belongs_to :department, optional: true
  has_many :visas,                dependent: :destroy
  has_many :employment_contracts, dependent: :destroy
  has_many :employee_assignments, dependent: :destroy
  has_many :assigned_projects, through: :employee_assignments, source: :project
  has_many :certifications,       dependent: :destroy
  has_many :leaves, class_name: "Leave", dependent: :destroy
  has_many :warnings, class_name: "EmployeeWarning", dependent: :destroy  # ISS-332

  # ISS-332+: UAE 노동법 — 활성 경고장 카운트 (3회 누적 시 해고 검토 권장)
  def active_warnings_count
    warnings.active.count
  end

  def warning_termination_threshold_reached?
    active_warnings_count >= EmployeeWarning::TERMINATION_THRESHOLD
  end

  def has_gross_misconduct?
    warnings.gross_misconduct.active.exists?
  end

  EMPLOYMENT_TYPES = %w[regular contract dispatch].freeze
  NATIONALITIES = {
    "AE" => "UAE", "KR" => "한국", "US" => "미국", "GB" => "영국",
    "IN" => "인도", "PH" => "필리핀", "PK" => "파키스탄", "EG" => "이집트",
    "JP" => "일본", "CN" => "중국", "DE" => "독일", "FR" => "프랑스"
  }.freeze
  AVATAR_COLORS = {
    "KR" => "bg-blue-500",   "AE" => "bg-emerald-500", "PH" => "bg-yellow-500",
    "IN" => "bg-orange-500", "PK" => "bg-green-600",   "EG" => "bg-amber-600",
    "US" => "bg-indigo-500", "GB" => "bg-violet-500",  "JP" => "bg-rose-500",
    "CN" => "bg-red-500",    "DE" => "bg-cyan-600",    "FR" => "bg-purple-500"
  }.freeze

  validates :name, :nationality, :employment_type, presence: true
  validates :employment_type, inclusion: { in: EMPLOYMENT_TYPES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # email 입력 시 같은 email의 User 찾아 자동 연결.
  # email 비우면 user_id도 끊는다 (수동 동기화 일관성).
  before_save :sync_user_by_email, if: :will_save_change_to_email?

  # ISS-296: active 또는 termination_date 변경 시 연결된 User 계정 활성화 상태 동기화
  # AtoZ 직원만 사용: user_id 새로 연결 시에도 활성화
  after_save :sync_user_account_status, if: -> { saved_change_to_active? || saved_change_to_termination_date? || saved_change_to_user_id? }

  def sync_user_by_email
    if email.present?
      matched = User.find_by("LOWER(email) = ?", email.downcase)
      self.user_id = matched&.id
    else
      self.user_id = nil
    end
  end

  # ISS-296: Employee 상태 변경 → 연결 User 계정 활성화 동기화
  def sync_user_account_status
    return unless user_id
    should_be_active = active && (termination_date.nil? || termination_date > Date.current)
    user.update_column(:active, should_be_active) if user.active != should_be_active
  end

  scope :active,     -> { where(active: true) }
  scope :by_name,    -> { order(:name) }
  scope :dispatched, -> { joins(:employee_assignments).where(employee_assignments: { status: "active" }).distinct }
  scope :unmapped,   -> { where(user_id: nil) }

  # AUDIT-005: 멘션 알림 미도달 방지 — user_id 미연결 직원에게 매핑 후보 제안
  def suggested_user
    return nil if user_id.present?
    # 1순위: 이메일 정확 매칭
    if email.present?
      user = User.find_by("LOWER(email) = ?", email.downcase)
      return user if user
    end
    # 2순위: 이름 정확 매칭
    User.find_by(name: name)
  end

  def current_contract   = employment_contracts.where(status: "active").order(start_date: :desc).first
  def current_assignment = employee_assignments.where(status: "active").order(start_date: :desc).first
  def active_visa        = visas.where(status: "active").order(expiry_date: :asc).first
  def current_project    = current_assignment&.project

  def display_name = name
  def initials = name.split.map(&:first).first(2).join.upcase
  def avatar_color = AVATAR_COLORS[nationality] || "bg-gray-500"

  def nationality_label = NATIONALITIES[nationality] || nationality

  def employment_type_label
    { "regular" => "정규직", "contract" => "계약직", "dispatch" => "파견" }[employment_type] || employment_type
  end

  # 올해 사용한 연차 일수
  def used_annual_leave_this_year
    leaves.approved.annual.this_year.sum(:days_requested).to_f
  end

  # 잔여 연차 (캐시된 annual_leave_balance - 올해 사용량)
  def remaining_annual_leave
    (annual_leave_balance - used_annual_leave_this_year).round(1)
  end

  # 정규직의 경우 연간 30일로 잔여 초기화
  def reset_annual_balance!(days = 30)
    update!(annual_leave_balance: days)
  end

  def visa_expiring_soon?
    return false unless active_visa
    active_visa.expiry_date <= 60.days.from_now.to_date
  end

  def contract_expiring_soon?
    return false unless current_contract&.end_date
    current_contract.end_date <= 30.days.from_now.to_date
  end

  def tenure_days
    return nil unless hire_date
    ((termination_date || Date.today) - hire_date).to_i
  end

  def tenure_label
    return nil unless hire_date
    total = tenure_days
    years  = total / 365
    months = (total % 365) / 30
    if years > 0
      "#{years}년 #{months}개월"
    elsif months > 0
      "#{months}개월"
    else
      "#{total}일"
    end
  end

  private

  def validate_avatar_safety
    return unless avatar.attached?
    blob = avatar.blob
    ctype = blob.content_type.to_s.downcase
    if !AVATAR_ALLOWED_MIMES.include?(ctype)
      errors.add(:avatar, "이미지 파일만 업로드 가능합니다 (JPEG/PNG/WebP/HEIC)")
      avatar.purge_later if blob.persisted?
    elsif blob.byte_size > AVATAR_MAX_SIZE
      mb = (blob.byte_size.to_f / 1.megabyte).round(1)
      errors.add(:avatar, "사진 크기 초과 (#{mb}MB > #{AVATAR_MAX_SIZE / 1.megabyte}MB)")
      avatar.purge_later if blob.persisted?
    end
  end
end
