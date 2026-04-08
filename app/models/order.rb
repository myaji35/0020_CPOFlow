class Order < ApplicationRecord
  include GraphNode

  belongs_to :user     # creator
  belongs_to :client,   optional: true
  belongs_to :supplier, optional: true
  belongs_to :project,  optional: true
  belongs_to :parent_order, class_name: "Order", optional: true
  has_many   :sub_orders, class_name: "Order", foreign_key: :parent_order_id,
             dependent: :nullify, inverse_of: :parent_order
  has_many :tasks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :assignments, dependent: :destroy
  has_many :assignees, through: :assignments, source: :employee
  has_many :order_quotes, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many_attached :attachments
  has_many :rfq_feedbacks, dependent: :destroy
  has_many :agent_insights, dependent: :destroy

  enum :status, {
    new_rfq: 0,
    make_quo: 1,
    pending_po: 2,
    new_po: 3,
    delivery_items: 4,
    problem: 5,
    get_grn: 6,
    give_up: 7,
    done: 8
  }, default: :new_rfq

  enum :rfq_status, {
    rfq_triage:   0,
    rfq_pending:  1,
    rfq_excluded: 2,
    rfq_archived: 3
  }, default: :rfq_pending, prefix: :rfq

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

  scope :active, -> { where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :overdue, -> { where("due_date < ?", Date.today).where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :urgent, -> { where("due_date <= ?", 7.days.from_now).where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :due_soon, -> { where(due_date: Date.today..14.days.from_now).where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :by_due_date, -> { order(due_date: :asc) }
  scope :by_reference_no, ->(ref) { where(reference_no: ref).order(created_at: :asc) }
  scope :root_orders, -> { where(parent_order_id: nil) }
  scope :inbox_pending, -> { where(status: :new_rfq, rfq_status: :rfq_pending) }
  scope :inbox_excluded, -> { where(status: :new_rfq, rfq_status: :rfq_excluded) }
  scope :inbox_triaged, -> { where(rfq_status: :rfq_triage) }

  # Phase F (ISS-034): 칸반 new_rfq 컬럼 게이트
  # rfq_triage 상태(견적성 확정)인 건만 칸반에 노출.
  # rfq_pending(미분류) / rfq_excluded(제외) / rfq_archived(보관)는 인박스에만 존재.
  # 다른 status(make_quo 이후)는 이미 변환된 카드이므로 rfq_status 무관하게 통과.
  KANBAN_VISIBLE_RFQ_STATUSES = %i[rfq_triage].freeze

  scope :kanban_visible_in_column, ->(column) {
    if column.to_s == "new_rfq"
      where(status: :new_rfq, rfq_status: KANBAN_VISIBLE_RFQ_STATUSES)
    else
      where(status: column)
    end
  }

  # rfq_status 가드: Order로의 변환(워크플로우 진입)이 허용되는지 여부
  # rfq_excluded(제외) / rfq_archived(보관) 상태는 칸반 진입 차단.
  def rfq_convertible?
    %w[rfq_triage rfq_pending].include?(rfq_status.to_s)
  end

  KANBAN_COLUMNS = %w[new_rfq make_quo pending_po new_po delivery_items problem get_grn give_up done].freeze

  STATUS_LABELS = {
    "new_rfq"        => "New(신규)",
    "make_quo"       => "Make QUO(견적작성)",
    "pending_po"     => "Pending PO(발주대기)",
    "new_po"         => "New PO(발주확정)",
    "delivery_items" => "Delivery Items(납품진행)",
    "problem"        => "Problem(문제)",
    "get_grn"        => "Get GRN(수령확인)",
    "give_up"        => "Give Up(포기)",
    "done"           => "Done(완료)"
  }.freeze

  # RE/FW 접두사 제거 + reference_no 분리한 간소화 제목 (표시용)
  def display_subject
    subject = original_email_subject.to_s.strip
    # 1. RE:/FW:/Fwd: 접두사 반복 제거
    subject = subject.sub(/\A\s*(RE|FW|Fwd)\s*:\s*/i, "").strip while subject.match?(/\A\s*(RE|FW|Fwd)\s*:/i)
    # 2. reference_no가 있으면 제목에서 해당 번호 제거 (배지로 별도 표시)
    #    RFQ_6000009486, RFQ-6000009486, RFQ 6000009486 패턴도 함께 제거
    if reference_no.present?
      escaped = Regexp.escape(reference_no)
      subject = subject.gsub(/(?:RFQ[_\-\s]?)?#{escaped}[.:;,]?\s*[-–—]?\s*/i, "").strip
    end
    # 3. "Event" 접두사 제거 (Ariba 이메일에서 반복되는 패턴)
    subject = subject.sub(/\AEvent\s+/i, "").strip
    # 4. RFQ/견적요청 접두사 제거 (별도 배지로 표시)
    subject = subject.sub(/\A(RFQ|견적요청)\s*[:：\-–—]?\s*/i, "").strip
    # 5. PR 번호 패턴 정리 (PR 1200010340 → 제거)
    subject = subject.gsub(/\bPR\s+\d{10}\b\s*/, "").strip
    # 6. 앞뒤 구분자(- : .) 정리
    subject = subject.gsub(/\A[-–—:.\s]+|[-–—:.\s]+\z/, "").strip
    subject.presence || title
  end

  SUBJECT_TAGS = {
    /reminder/i  => "Reminder",
    /revised/i   => "Revised",
    /cancel/i    => "Cancelled",
    /urgent/i    => "Urgent",
    /update/i    => "Updated",
    /extend/i    => "Extended",
    /final/i     => "Final"
  }.freeze

  # 제목에서 상태 키워드 태그 추출
  def subject_tags
    tags = []
    subject = original_email_subject.to_s
    SUBJECT_TAGS.each { |pattern, label| tags << label if subject.match?(pattern) }
    tags.uniq.first(3)
  end

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
    return unless status == "new_po"
    return if ecount_slip_no.present?

    EcountSlipCreateJob.perform_later(id)
  end
end
