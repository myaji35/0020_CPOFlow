class Order < ApplicationRecord
  belongs_to :user     # creator
  belongs_to :client,   optional: true
  belongs_to :supplier, optional: true
  belongs_to :project,  optional: true
  has_many :tasks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :assignments, dependent: :destroy
  has_many :assignees, through: :assignments, source: :employee
  has_many :order_quotes, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many_attached :attachments
  has_many :rfq_feedbacks, dependent: :destroy

  enum :status, {
    inbox: 0,
    reviewing: 1,
    quoted: 2,
    confirmed: 3,
    procuring: 4,
    qa: 5,
    delivered: 6
  }, default: :inbox

  enum :rfq_status, {
    rfq_confirmed: 0,
    rfq_uncertain: 1,
    rfq_excluded:  2
  }, default: :rfq_confirmed, prefix: :rfq

  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }, default: :medium

  enum :source_type, {
    email: 0,
    ariba: 1
  }, default: :email

  validates :title, presence: true
  validates :customer_name, presence: true
  validates :status, presence: true

  scope :active, -> { where.not(status: :delivered) }
  scope :overdue, -> { where("due_date < ?", Date.today).where.not(status: :delivered) }
  scope :urgent, -> { where("due_date <= ?", 7.days.from_now).where.not(status: :delivered) }
  scope :due_soon, -> { where(due_date: Date.today..14.days.from_now).where.not(status: :delivered) }
  scope :by_due_date, -> { order(due_date: :asc) }
  scope :by_reference_no, ->(ref) { where(reference_no: ref).order(created_at: :asc) }

  KANBAN_COLUMNS = %w[inbox reviewing quoted confirmed procuring qa delivered].freeze

  STATUS_LABELS = {
    "inbox"     => "Inbox",
    "reviewing" => "Under Review",
    "quoted"    => "Quoted",
    "confirmed" => "Order Confirmed",
    "procuring" => "Procuring",
    "qa"        => "QA Inspection",
    "delivered" => "Delivered"
  }.freeze

  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end

  def due_urgency
    days = days_until_due
    return :overdue if days&.negative?
    return :urgent  if days && days <= 7
    return :warning if days && days <= 14
    :normal
  end

  def due_badge_class
    case due_urgency
    when :overdue then "badge-danger"
    when :urgent  then "badge-danger"
    when :warning then "badge-warning"
    else               "badge-success"
    end
  end

  def task_progress
    return { done: 0, total: 0 } if tasks.empty?
    { done: tasks.where(completed: true).count, total: tasks.count }
  end

  def tags_array
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # 이메일 서명 JSON → Hash
  def email_signature
    return {} if email_signature_json.blank?
    JSON.parse(email_signature_json).transform_keys(&:to_sym)
  rescue JSON::ParserError
    {}
  end

  # 서명에서 추출한 발신자 이름
  def sender_name
    email_signature[:name].presence ||
      original_email_from.to_s.match(/^([^<]+)</)&.[](1)&.strip
  end

  # 서명에서 추출한 발신자 회사명
  def sender_company
    email_signature[:company].presence || customer_name
  end

  # 이메일 본문에서 서명을 분리한 본문만 반환
  def body_without_signature
    Gmail::EmailSignatureParserService.split(
      original_email_body.to_s, original_email_html_body
    )[:body]
  end

  # 이메일 본문에서 분리된 서명 블록 텍스트 반환
  def signature_block_text
    Gmail::EmailSignatureParserService.split(
      original_email_body.to_s, original_email_html_body
    )[:signature]
  end

  # eCountERP 전표 자동 생성 — confirmed 상태 전환 시 트리거
  after_update_commit :enqueue_ecount_slip, if: :saved_change_to_status?

  private

  def enqueue_ecount_slip
    return unless status == "confirmed"
    return if ecount_slip_no.present?

    EcountSlipCreateJob.perform_later(id)
  end
end
