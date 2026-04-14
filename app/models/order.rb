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

  belongs_to :card_status, optional: true

  # 기본값 보장: 새 Order는 default(normal)로 시작
  before_validation :ensure_card_status, on: :create

  # 저장 후 자동 배정: 수동 지정 없으면 규칙 재평가
  after_save :maybe_auto_assign_card_status, if: :should_auto_reassign?

  enum :source_type, {
    email: 0,
    ariba: 1
  }, default: :email

  validates :title, presence: true
  validates :customer_name, presence: true
  validates :status, presence: true

  scope :active, -> { where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :overdue, -> { where("due_date < ?", Date.today).where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :urgent, -> {
    joins(:card_status)
      .where(card_statuses: { key: %w[urgent high overdue] })
      .where.not(status: [ :get_grn, :give_up, :done ])
  }
  scope :due_soon, -> { where(due_date: Date.today..14.days.from_now).where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :by_due_date, -> { order(due_date: :asc) }
  scope :by_reference_no, ->(ref) { where(reference_no: ref).order(created_at: :asc) }
  scope :root_orders, -> { where(parent_order_id: nil) }
  scope :inbox_pending, -> { where(status: :new_rfq, rfq_status: :rfq_pending) }
  scope :inbox_excluded, -> { where(status: :new_rfq, rfq_status: :rfq_excluded) }
  scope :inbox_triaged, -> { where(rfq_status: :rfq_triage) }
  scope :not_archived,  -> { where(archived_at: nil) }
  scope :archived,      -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  # ISS-039: urgent/high + 마감일 경과 + 담당자 미배정 = 즉시 조치 필요
  scope :critical, -> {
    joins(:card_status)
      .where(card_statuses: { key: %w[urgent high overdue] })
      .where("due_date < ?", Date.today)
      .where.not(status: [ :get_grn, :give_up, :done ])
      .left_joins(:assignments)
      .where(assignments: { id: nil })
      .distinct
  }

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

  # ISS-039: 담당자 미배정 여부
  def unassigned?
    assignees.empty?
  end

  # ISS-039: urgent/high + 마감일 경과 + 담당자 미배정 = 즉시 조치 필요
  def critical?
    return false unless card_status
    return false unless %w[urgent high overdue].include?(card_status.key)
    return false unless due_date.present? && due_date < Date.today
    return false if %w[get_grn give_up done].include?(status.to_s)
    unassigned?
  end

  # 카드 색상 헬퍼 — 뷰 반복 호출 간소화
  def card_bg_color;     card_status&.bg_color     || "#FAFAFA"; end
  def card_border_color; card_status&.border_color || "#E5E7EB"; end
  def card_text_color;   card_status&.text_color   || "#374151"; end

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

  # M1-Task4: Order status 전환 → 자동 링크 생성 (ontology)
  after_update :create_status_transition_link, if: :saved_change_to_status?

  # M1-Task5: parent_order_id 변경 → derived_from 자동 링크 생성 (ontology)
  after_update :create_derived_from_link, if: :saved_change_to_parent_order_id?

  # M3-Task1: Order 생성 시 heuristic 제안 Job enqueue (ontology)
  after_create_commit { SuggestOrderLinksJob.perform_later(id) }

  private

  def ensure_card_status
    self.card_status ||= CardStatus.default
  end

  def should_auto_reassign?
    card_status_manually_set_at.blank? &&
      (saved_change_to_due_date? || saved_change_to_card_status_id?)
  end

  def maybe_auto_assign_card_status
    target = CardStatus::AutoAssigner.call(self)
    return unless target
    return if target.id == card_status_id
    update_column(:card_status_id, target.id)
  end

  def create_derived_from_link
    return if parent_order_id.blank?

    OrderLink.find_or_create_by!(
      source_type: "Order",
      source_id:   id,                # 후속(child)
      target_type: "Order",
      target_id:   parent_order_id,   # 원본(parent)
      relation:    "derived_from"
    ) do |link|
      link.status     = OrderLink::STATUSES.first  # "confirmed"
      link.confidence = 1.0
      link.metadata   = {
        "source"  => "system_event",
        "trigger" => "parent_order_id_changed"
      }
    end
  end

  def create_status_transition_link
    return if parent_order_id.blank?

    prev, curr = saved_change_to_status
    relation = case
    when prev == "pending_po" && curr == "new_po"
                 "confirmed_to"
    when curr == "get_grn"
                 "delivered_as"
    end
    return unless relation

    OrderLink.find_or_create_by!(
      source_type: "Order",
      source_id:   parent_order_id,
      target_type: "Order",
      target_id:   id,
      relation:    relation
    ) do |link|
      link.status     = OrderLink::STATUSES.first  # "confirmed"
      link.confidence = 1.0
      link.metadata   = {
        "source"  => "system_event",
        "trigger" => "status_transition:#{prev}->#{curr}"
      }
    end
  end

  def enqueue_ecount_slip
    return unless status == "new_po"
    return if ecount_slip_no.present?

    EcountSlipCreateJob.perform_later(id)
  end
end
