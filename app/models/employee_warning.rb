# ISS-332+: UAE Federal Decree-Law No. 33 of 2021 (Articles 39, 41, 44) 기반 경고장
# 모델명: EmployeeWarning (Ruby ::Warning 모듈 충돌 회피)
# 테이블: warnings (마이그 변경 없음)
class EmployeeWarning < ApplicationRecord
  self.table_name = "warnings"

  # === UAE Art.44 즉시 해고 사유 + 일반 위반 카테고리 ===
  CATEGORIES = %w[
    tardiness absence unauthorized_absence quality safety behavior
    confidentiality_breach assault intoxication damage_to_property
    false_documents insubordination other
  ].freeze

  # === UAE Art.39 7단계 징계 처벌 ===
  SEVERITIES = %w[
    caution written_warning wage_deduction suspension
    bonus_deprivation promotion_deprivation termination
  ].freeze

  STATUSES = %w[active acknowledged expired revoked].freeze

  # 3회 누적 시 해고 검토 알림 (UAE 실무 관행)
  TERMINATION_THRESHOLD = 3

  belongs_to :employee
  belongs_to :issued_by, class_name: "User", optional: true
  has_many_attached :documents

  validates :issued_at, :subject, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status,   inclusion: { in: STATUSES }
  validates :wage_deduction_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 5 }, allow_nil: true
  validates :suspension_days,     numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 14 }, allow_nil: true

  scope :active,            -> { where(status: "active") }
  scope :recent,            -> { order(issued_at: :desc) }
  scope :gross_misconduct,  -> { where(gross_misconduct: true) }
  scope :mohre_reportable,  -> { where(mohre_reportable: true) }
  scope :for_severity,      ->(s) { where(severity: s) }

  CATEGORY_LABELS = {
    "tardiness"             => "지각 (Tardiness)",
    "absence"               => "결근 (Absence)",
    "unauthorized_absence"  => "무단결근 (Unauthorized Absence — Art.44: 7일 연속/20일 단속 시 즉시 해고)",
    "quality"               => "품질 (Quality)",
    "safety"                => "안전 (Safety)",
    "behavior"              => "행위 위반 (Behavior)",
    "confidentiality_breach" => "기밀 누설 (Art.44 — 즉시 해고)",
    "assault"               => "폭행 (Art.44 — 즉시 해고)",
    "intoxication"          => "음주/약물 (Art.44 — 즉시 해고)",
    "damage_to_property"    => "회사 손실 야기 (Art.44 — 즉시 해고)",
    "false_documents"       => "신분/문서 위조 (Art.44 — 즉시 해고)",
    "insubordination"       => "상관 명령 불복 (Insubordination)",
    "other"                 => "기타 (Other)"
  }.freeze

  SEVERITY_LABELS = {
    "caution"               => "1단계: 구두 주의 (Art.39-1 Caution)",
    "written_warning"       => "2단계: 서면 경고 (Art.39-2 Written Warning)",
    "wage_deduction"        => "3단계: 임금 감액 (Art.39-3, 월 5일 이내)",
    "suspension"            => "4단계: 무급 정직 (Art.39-4, 최대 14일)",
    "bonus_deprivation"     => "5단계: 보너스 박탈 (Art.39-5, 최대 1년)",
    "promotion_deprivation" => "6단계: 승진 제한 (Art.39-6, 최대 2년)",
    "termination"           => "7단계: 해고 (Art.39-7, 퇴직금 보존)"
  }.freeze

  STATUS_LABELS = {
    "active" => "활성", "acknowledged" => "확인됨", "expired" => "만료", "revoked" => "철회"
  }.freeze

  # Art.44 즉시 해고 사유 자동 식별
  ART44_CATEGORIES = %w[unauthorized_absence confidentiality_breach assault intoxication damage_to_property false_documents].freeze

  before_validation :auto_detect_gross_misconduct
  before_save :auto_set_article_reference

  def category_label;  CATEGORY_LABELS[category]  || category;  end
  def severity_label;  SEVERITY_LABELS[severity]  || severity;  end
  def status_label;    STATUS_LABELS[status]      || status;    end

  def severity_badge_class
    case severity
    when "caution"               then "bg-yellow-100 text-yellow-800"
    when "written_warning"       then "bg-orange-100 text-orange-800"
    when "wage_deduction"        then "bg-amber-200 text-amber-900"
    when "suspension"            then "bg-red-100 text-red-800"
    when "bonus_deprivation"     then "bg-red-200 text-red-900"
    when "promotion_deprivation" then "bg-red-300 text-red-900"
    when "termination"           then "bg-gray-900 text-white"
    end
  end

  def status_badge_class
    case status
    when "active"       then "bg-red-50 text-red-700 border border-red-200"
    when "acknowledged" then "bg-blue-50 text-blue-700 border border-blue-200"
    when "expired"      then "bg-gray-50 text-gray-500 border border-gray-200"
    when "revoked"      then "bg-gray-100 text-gray-400 border border-gray-300 line-through"
    end
  end

  # Art.41 서면 통지 완료 여부
  def notification_complete?
    notified_at.present?
  end

  # 직원 진술 접수 여부
  def employee_responded?
    response_received_at.present? || employee_response.present?
  end

  private

  def auto_detect_gross_misconduct
    self.gross_misconduct = ART44_CATEGORIES.include?(category) || severity == "termination"
    self.visa_action_required = true if gross_misconduct && severity == "termination"
  end

  def auto_set_article_reference
    self.article_reference =
      if gross_misconduct
        "UAE Federal Decree-Law 33/2021 — Art.44 (Gross Misconduct)"
      else
        "UAE Federal Decree-Law 33/2021 — Art.39 (Disciplinary Penalties)"
      end
  end
end
