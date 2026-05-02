# ISS-332: 경고장 — 인사 처분 기록
class Warning < ApplicationRecord
  CATEGORIES = %w[tardiness absence quality safety behavior other].freeze
  SEVERITIES = %w[verbal written final suspension termination].freeze
  STATUSES   = %w[active acknowledged expired revoked].freeze

  belongs_to :employee
  belongs_to :issued_by, class_name: "User", optional: true
  has_many_attached :documents

  validates :issued_at, :subject, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status,   inclusion: { in: STATUSES }

  scope :active,       -> { where(status: "active") }
  scope :recent,       -> { order(issued_at: :desc) }
  scope :for_severity, ->(s) { where(severity: s) }

  CATEGORY_LABELS = {
    "tardiness" => "지각", "absence" => "무단결근", "quality" => "품질",
    "safety" => "안전", "behavior" => "행위", "other" => "기타"
  }.freeze
  SEVERITY_LABELS = {
    "verbal" => "구두 경고", "written" => "서면 경고", "final" => "최종 경고",
    "suspension" => "정직", "termination" => "해고"
  }.freeze
  STATUS_LABELS = {
    "active" => "활성", "acknowledged" => "확인됨", "expired" => "만료", "revoked" => "철회"
  }.freeze

  def category_label;  CATEGORY_LABELS[category]  || category;  end
  def severity_label;  SEVERITY_LABELS[severity]  || severity;  end
  def status_label;    STATUS_LABELS[status]      || status;    end

  def severity_badge_class
    case severity
    when "verbal"      then "bg-yellow-100 text-yellow-800"
    when "written"     then "bg-orange-100 text-orange-800"
    when "final"       then "bg-red-100 text-red-800"
    when "suspension"  then "bg-red-200 text-red-900"
    when "termination" then "bg-gray-900 text-white"
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
end
