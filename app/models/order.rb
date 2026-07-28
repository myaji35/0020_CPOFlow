class Order < ApplicationRecord
  include GraphNode

  belongs_to :user     # creator
  belongs_to :client,   optional: true
  belongs_to :supplier, optional: true
  belongs_to :project,  optional: true
  belongs_to :contact_person, optional: true
  belongs_to :parent_order, class_name: "Order", optional: true
  has_many   :sub_orders, class_name: "Order", foreign_key: :parent_order_id,
             dependent: :nullify, inverse_of: :parent_order
  has_many :tracking_numbers, dependent: :destroy
  has_many :tracking_codes,   through: :tracking_numbers
  has_many :tasks, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :assignments, dependent: :destroy
  has_many :assignees, through: :assignments, source: :employee
  has_many :order_quotes, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many :rfq_auto_analyses, dependent: :destroy
  # IMPORTANT: AQA는 active_storage_attachments FK를 가지므로,
  # has_many_attached :attachments 보다 먼저 선언해야 before_destroy 순서가 보장됨.
  # 순서를 바꾸면 Order.destroy 시 FK violation 발생. 하단 마이그레이션 cascade FK도 참조.
  has_many :attachment_quote_analyses, dependent: :destroy
  has_many_attached :attachments

  has_many :quote_items, class_name: "OrderQuoteItem", dependent: :destroy

  # ISS-262: 악성 첨부 차단 — MIME allowlist + 실행가능 확장자 deny + 크기 상한
  # 검증은 attach 시점(validate) — attach 후 blob 저장 전에 탈락.
  ATTACHMENT_ALLOWED_CONTENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    application/vnd.ms-excel.sheet.macroEnabled.12
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/msword
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/vnd.ms-powerpoint
    image/jpeg image/pjpeg image/png image/gif image/webp image/heic image/heif image/svg+xml
    application/zip application/x-zip-compressed application/x-7z-compressed application/x-rar-compressed
    text/csv text/plain text/html
    application/x-hwp application/haansofthwp application/vnd.hancom.hwp
    application/octet-stream
    message/rfc822
  ].freeze

  ATTACHMENT_DENY_EXTENSIONS = %w[
    exe bat cmd com sh ps1 psm1 msi dll jar js vbs vbe wsf wsh scr cpl hta
    reg py pyc rb pl php app deb rpm apk ipa pkg dmg iso img bin
  ].freeze

  ATTACHMENT_MAX_SIZE = 50.megabytes

  validate :validate_attachment_safety
  validate :validate_status_transition, on: :update, if: :will_save_change_to_status?

  # ISS-265: 관리자가 의도적으로 규칙을 우회해야 할 때 사용 (예: 데이터 정정)
  # ex) order.force_transition = true; order.update(status: :new_rfq)
  attr_accessor :force_transition

  # ISS-265: 칸반 상태 전이 규칙 — 건너뛰기/역행 차단
  # 허용 전이 매트릭스:
  #   new_rfq        → make_quo, give_up
  #   make_quo       → pending_po, give_up, new_rfq(견적 취소)
  #   pending_po     → new_po, give_up, make_quo(견적 수정 복귀)
  #   new_po         → delivery_items, problem, give_up
  #   delivery_items → get_grn, problem, give_up
  #   problem        → delivery_items, get_grn, give_up, new_po(재발주)
  #   get_grn        → done, problem(수령 문제)
  #   give_up        → new_rfq(재개)
  #   done           → (terminal, 재오픈 금지)
  STATUS_TRANSITIONS = {
    "new_rfq"        => %w[make_quo give_up],
    "make_quo"       => %w[pending_po give_up new_rfq],
    "pending_po"     => %w[new_po give_up make_quo],
    "new_po"         => %w[delivery_items problem give_up],
    "delivery_items" => %w[get_grn problem give_up],
    "problem"        => %w[delivery_items get_grn give_up new_po],
    "get_grn"        => %w[done problem],
    "give_up"        => %w[new_rfq],
    "done"           => []
  }.freeze

  private

  def validate_attachment_safety
    return unless attachments.attached?

    attachments.each do |att|
      blob = att.blob
      ext = File.extname(blob.filename.to_s).delete(".").downcase
      content_type = blob.content_type.to_s.downcase

      if ATTACHMENT_DENY_EXTENSIONS.include?(ext)
        errors.add(:attachments, "허용되지 않은 파일 형식입니다: .#{ext} (#{blob.filename})")
        att.purge_later
        next
      end

      # octet-stream(알 수 없음)은 확장자로 보조 판단 — deny 아닌 확장자만 통과
      if content_type == "application/octet-stream"
        # 위 deny 검사에서 이미 걸렀으므로 여기서는 통과
      elsif !ATTACHMENT_ALLOWED_CONTENT_TYPES.include?(content_type)
        errors.add(:attachments, "허용되지 않은 MIME 타입입니다: #{content_type} (#{blob.filename})")
        att.purge_later
        next
      end

      if blob.byte_size.to_i > ATTACHMENT_MAX_SIZE
        mb = (blob.byte_size.to_f / 1.megabyte).round(1)
        errors.add(:attachments, "파일이 너무 큽니다: #{mb}MB (최대 #{ATTACHMENT_MAX_SIZE / 1.megabyte}MB, #{blob.filename})")
        att.purge_later
      end
    end
  end

  # ISS-265: 칸반 상태 전이 guard — STATUS_TRANSITIONS에 없는 전이는 차단
  def validate_status_transition
    return if force_transition  # admin 수동 정정 우회
    from = status_was.to_s
    to   = status.to_s
    return if from.blank? || from == to
    allowed = STATUS_TRANSITIONS[from] || []
    unless allowed.include?(to)
      errors.add(:status, "허용되지 않은 상태 전이입니다: #{from} → #{to} (허용: #{allowed.join(', ').presence || '없음'})")
    end
  end

  public
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
  belongs_to :kanban_board, optional: true
  belongs_to :kanban_column, optional: true

  # ISS-376: 칸반 실시간 동기화 — 카드 변경 시 같은 보드를 보는 모든 클라이언트로 page refresh 브로드캐스트.
  # Turbo morph가 DOM diff로 처리하므로 깜빡임 없이 스크롤 위치 유지됨.
  # 보드 없는(legacy) Order는 default 보드 스트림으로 fallback.
  after_create_commit  -> { broadcast_refresh_to(broadcast_kanban_stream) }
  after_update_commit  -> { broadcast_refresh_to(broadcast_kanban_stream) }
  after_destroy_commit -> { broadcast_refresh_to(broadcast_kanban_stream) }

  # 기본값 보장: 새 Order는 default(normal)로 시작
  before_validation :ensure_card_status, on: :create
  before_validation :backfill_customer_name_from_client
  after_save :sync_legacy_tracking_columns_to_numbers
  # AUDIT-002: 신규 Order 생성 시 담당자 미배정이면 자동 배정 시도
  after_create_commit :auto_assign_if_blank

  # 저장 후 자동 배정: 수동 지정 없으면 규칙 재평가
  after_save :maybe_auto_assign_card_status, if: :should_auto_reassign?

  enum :source_type, {
    email: 0,
    ariba: 1
  }, default: :email

  validates :title, presence: true
  validates :customer_name, presence: true, unless: -> { client_id.present? }
  validates :status, presence: true

  scope :active, -> { where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :overdue, -> { where("due_date < ?", Date.today).where.not(status: [ :get_grn, :give_up, :done ]) }
  scope :urgent, -> {
    joins(:card_status)
      .where(card_statuses: { key: %w[urgent high overdue] })
      .where.not(status: [ :get_grn, :give_up, :done ])
  }
  scope :due_soon, -> { where(due_date: Date.today..14.days.from_now).where.not(status: [ :get_grn, :give_up, :done ]) }
  # JOIN 환경(scoped_orders 등)에서 다른 테이블의 동명 컬럼과 충돌 방지를 위해 테이블명 명시.
  scope :by_due_date, -> { order("orders.due_date ASC") }
  scope :by_reference_no, ->(ref) { where(reference_no: ref).order("orders.created_at ASC") }
  scope :root_orders, -> { where(parent_order_id: nil) }
  scope :inbox_pending, -> { where(status: :new_rfq, rfq_status: :rfq_pending) }
  scope :inbox_excluded, -> { where(status: :new_rfq, rfq_status: :rfq_excluded) }
  scope :inbox_triaged, -> { where(rfq_status: :rfq_triage) }
  scope :not_archived,  -> { where(archived_at: nil) }
  scope :archived,      -> { where.not(archived_at: nil) }
  # LAB / RFQ Auto — 샌드박스 Order는 운영 화면(칸반/inbox/리포트)에서 제외.
  # 운영 영역에서 무조건 .not_sandbox 적용 (scoped_orders가 자동 적용).
  scope :not_sandbox,   -> { where(lab_sandbox: false) }
  scope :sandbox_only,  -> { where(lab_sandbox: true) }

  # AUDIT-001: new_rfq 컬럼 누적 정리 — 30일 기준으로 stale/recent 분리
  scope :stale_new_rfq,  -> { where(status: :new_rfq).where("orders.updated_at < ?", 30.days.ago) }
  scope :recent_new_rfq, -> { where(status: :new_rfq).where("orders.updated_at >= ?", 30.days.ago) }

  def archived?
    archived_at.present?
  end

  # 카드를 휴지통으로 보냄. 자식(sub_orders)도 함께 archived.
  # 2026-04-29: 자식이 nullify 로 살아남아 칸반에 "3개씩 새로 생기는 느낌" 차단.
  # 자식 카드들도 같은 trash 사이클에 함께 묶어 사용자 의도(부모 삭제 = 전체 삭제) 보장.
  def archive!
    Order.transaction do
      now = Time.current
      update!(archived_at: now)
      # 자식들도 함께 archive (이미 archived 인 자식은 그대로)
      sub_orders.where(archived_at: nil).update_all(archived_at: now)
    end
  end

  # 좀비 차단 가드 — 같은 reference_no 또는 gmail_thread_id 중 하나라도
  # archived(휴지통) 상태로 존재하는지 검사.
  # EmailToOrderService 가 새 카드 생성 시 호출 → true 면 신규 카드도 archived 로 시작.
  # "분리 운영 원칙": 칸반에서 삭제한 RFQ 는 거래처가 같은 건의 후속 메일을 보내도
  # 다시 칸반/인박스에 등장하지 않는다. 명시 복원(restore!)만이 archived_at 을 푼다.
  def self.trashed_lineage?(reference_no: nil, gmail_thread_id: nil)
    ref = reference_no.to_s.strip
    tid = gmail_thread_id.to_s.strip
    return false if ref.blank? && tid.blank?

    rel = archived
    if ref.present? && tid.present?
      rel = rel.where("reference_no = ? OR gmail_thread_id = ?", ref, tid)
    elsif ref.present?
      rel = rel.where(reference_no: ref)
    else
      rel = rel.where(gmail_thread_id: tid)
    end
    rel.exists?
  end

  # 휴지통에서 복원 — archived_at clear. 자식도 같은 사이클에 복원.
  def restore!
    Order.transaction do
      update!(archived_at: nil)
      sub_orders.where.not(archived_at: nil).update_all(archived_at: nil)
    end
  end

  # 영구 삭제 — DB에서 완전히 제거 (복구 불가)
  def destroy_permanently!
    destroy
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

  # AUDIT-003: 단계별 기본 SLA 일수 — 추후 Settings에서 관리 가능하도록 단순 hash 유지
  DEFAULT_SLA_DAYS = {
    new_rfq:        3,
    make_quo:       5,
    pending_po:     7,
    new_po:         14,
    delivery_items: 21,
    problem:        7,
    get_grn:        3
  }.freeze

  # AUDIT-003: due_date 미설정 Order의 기본 마감일 계산
  # target_status 미지정 시 현재 status 기준으로 계산
  def default_due_date_for(target_status = nil)
    status_key = (target_status || status).to_sym
    days = DEFAULT_SLA_DAYS[status_key] || 7
    (created_at || Time.current) + days.days
  end

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
  # 사용자가 title을 수동 편집한 경우(original_email_subject와 불일치) 편집본 우선
  def display_subject
    orig = original_email_subject.to_s.strip
    user_title = title.to_s.strip
    if user_title.present? && orig.present? && user_title != orig
      return user_title
    end
    subject = orig
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

  # 2026-04-29: 신규 발주 기본 마감일이 D+7로 변경됨에 따라 임계값 재조정.
  # 이전: urgent ≤7d, warning ≤14d (모든 신규 발주가 urgent 가 되어버려 의미 없음)
  # 변경: urgent ≤3d (정말 임박한 것만 빨강), warning ≤7d (1주 이내), normal 그 외.
  def due_urgency
    days = days_until_due
    return :overdue if days&.negative?
    return :urgent  if days && days <= 3
    return :warning if days && days <= 7
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

  # ISS-397: RFP 체크리스트 추출 결과 JSON → Hash
  def rfp_checklist
    return {} if rfp_checklist_json.blank?
    parsed = JSON.parse(rfp_checklist_json)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # ISS-397: 화면 표시용 행 목록 — 값이 없으면 nil(미추출)로 정직하게 표기
  def rfp_checklist_rows
    data = rfp_checklist
    defs = ChecklistItem.active.ordered.to_a
    defs = data.keys.map { |k| ChecklistItem.new(code: k, name: k) } if defs.empty?
    defs.map do |ci|
      raw = data[ci.code]
      value = raw.is_a?(Array) ? raw.reject(&:blank?).join(", ") : raw.to_s
      value = nil if value.blank?
      { code: ci.code, name: ci.name.presence || ci.code, value: value, present: value.present? }
    end
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

  # ISS-376: broadcast 대상 stream key.
  # 같은 보드를 보는 사용자만 받도록 보드 단위로 격리.
  def broadcast_kanban_stream
    board = kanban_board || KanbanBoard.default_board.first
    [ board, :kanban ]
  end

  def auto_assign_if_blank
    AutoAssignerService.new(self).call
  rescue => e
    Rails.logger.warn "[AutoAssigner] order##{id} 배정 실패: #{e.message}"
  end

  def ensure_card_status
    self.card_status ||= CardStatus.default
  end

  def backfill_customer_name_from_client
    return if customer_name.present?
    self.customer_name = client&.name
  end

  # 레거시 컬럼(rfq_no/quo_no/po_no)이 직접 변경된 경우(이메일 파서, quick_update 등)
  # → tracking_numbers 신규 구조에도 동기화해 카드/드로어 표시 일관성 유지.
  # TrackingNumber#sync_legacy_column 콜백이 무한 루프를 일으키지 않도록
  # update_columns 사용한 변경은 콜백을 거치지 않으므로 안전.
  LEGACY_TRACKING_FIELDS = { rfq_no: "RFQ", quo_no: "QUO", po_no: "PO" }.freeze

  def sync_legacy_tracking_columns_to_numbers
    LEGACY_TRACKING_FIELDS.each do |field, code|
      next unless saved_change_to_attribute?(field)
      val = read_attribute(field)
      tc = TrackingCode.find_by(code: code)
      next unless tc
      tn = tracking_numbers.find_or_initialize_by(tracking_code_id: tc.id)
      if val.blank?
        tn.destroy if tn.persisted?
      elsif tn.value != val
        tn.value = val
        tn.save(validate: true)
      end
    end
  rescue ActiveRecord::RecordNotFound
    # tracking_codes 시드 미적용 환경(드뭄) — 무시
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

  public

  # ISS-307: 첨부파일별 자동 분류 결과 (Rails.cache 24시간 캐시)
  def attachment_kinds
    attachments.includes(:blob).map do |att|
      Rails.cache.fetch("attachment_kind/#{att.blob.key}", expires_in: 24.hours) do
        Rfp::AttachmentClassifier.call(att)
      end
    end
  end

  # ISS-353 Phase 1 — 멘션 카운터 캐시 재계산 (worst-state aggregation)
  #
  # 의도적으로 update_columns 사용 — Order 콜백을 우회한다:
  #   - sync_legacy_tracking_columns_to_numbers (after_save)
  #   - maybe_auto_assign_card_status (after_save)
  #   - lock_version 충돌 회피 (carrier 콜백 무발화)
  # 멘션 요약 컬럼은 비즈니스 상태가 아닌 파생 캐시이므로 콜백/검증/optimistic locking 모두 우회 안전.
  # 멱등성: 매 호출마다 GROUP BY로 처음부터 재집계 → race condition 시 마지막 호출이 정확한 값으로 수렴.
  def recompute_mention_summary!
    rows = Notification.where(notifiable: self, notification_type: "mentioned")
                       .group(:user_id)
                       .pluck(
                         :user_id,
                         Arel.sql("MAX(CASE WHEN acknowledged_at IS NOT NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(CASE WHEN viewed_at IS NOT NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(CASE WHEN sla_due_at IS NOT NULL AND sla_due_at < CURRENT_TIMESTAMP AND acknowledged_at IS NULL THEN 1 ELSE 0 END)"),
                         Arel.sql("MAX(intent_level)")
                       )

    counts = { ack: 0, viewed_only: 0, unread: 0, sla_overdue: 0 }
    worst_intent = 0
    rows.each do |_uid, ack, viewed, overdue, intent|
      worst_intent = [ worst_intent, intent.to_i ].max
      if overdue == 1
        counts[:sla_overdue] += 1
      elsif ack == 1
        counts[:ack] += 1
      elsif viewed == 1
        counts[:viewed_only] += 1
      else
        counts[:unread] += 1
      end
    end

    worst = if counts[:sla_overdue] > 0 then "sla_overdue"
    elsif counts[:unread] > 0 then "unread"
    elsif counts[:viewed_only] > 0 then "viewed_only"
    elsif counts[:ack] > 0 then "acknowledged"
    else nil
    end

    update_columns(
      mention_total_count:        rows.size,
      mention_unread_count:       counts[:unread],
      mention_viewed_only_count:  counts[:viewed_only],
      mention_acknowledged_count: counts[:ack],
      mention_sla_overdue_count:  counts[:sla_overdue],
      mention_worst_state:        worst,
      mention_worst_intent:       worst_intent,
      updated_at:                 Time.current
    )
  end

  # ISS-353 Phase 1 — 도트 줄 렌더용 요약 hash 배열
  # 정렬: 미확인 우선 (○ → ◐ → ●) — spec §4 결정 4
  # B1-b: viewer 클라이언트 마킹 — viewer 인자는 Phase 3에서 활용 예정 (현재 미사용)
  def mention_summary_dots(viewer: nil, limit: 5)
    _ = viewer  # B1-b: viewer 클라이언트 마킹 — Phase 1에서는 미사용 (Phase 3 hover 카드용 예약)
    Notification.where(notifiable: self, notification_type: "mentioned")
                .group(:user_id)
                .order(Arel.sql("MIN(acknowledged_at) IS NULL DESC, MIN(viewed_at) IS NULL DESC"))
                .pluck(
                  :user_id,
                  Arel.sql("MAX(CASE WHEN acknowledged_at IS NOT NULL THEN 1 ELSE 0 END)"),
                  Arel.sql("MAX(CASE WHEN viewed_at IS NOT NULL THEN 1 ELSE 0 END)"),
                  Arel.sql("MAX(id)"),
                  Arel.sql("MAX(intent_level)")  # ISS-354 Phase 2: 도트 인텐트 색상 변형
                )
                .first(limit)
                .map do |uid, ack, viewed, nid, intent|
                  state = if ack == 1 then "acknowledged"
                  elsif viewed == 1 then "viewed_only"
                  else "unread"
                  end
                  user = User.find_by(id: uid)
                  {
                    user_id: uid,
                    user_name: user&.display_name || "?",
                    state: state,
                    notification_id: nid,
                    intent_level: intent.to_i
                  }
                end
  end

  # ISS-354 Phase 2 — 발신자(viewer) 본인이 이 카드에서 보낸 멘션 요약.
  # B3 결정: notifications.sent_by_user_id 로 정확히 매칭 (Order 생성자 휴리스틱 폐기).
  # 컴포넌트 B 호버 카드 / 리마인드 권한 / cooldown 판정에 사용.
  def sender_mention_summary(viewer:)
    return [] if viewer.nil?
    sent_notifs = notifications.where(notification_type: "mentioned", sent_by_user_id: viewer.id)
    return [] if sent_notifs.empty?

    sent_notifs.group_by(&:user_id).map do |_uid, group|
      latest = group.max_by(&:created_at)
      state = if latest.acknowledged_at.present? then :acknowledged
      elsif latest.viewed_at.present?  then :viewed_only
      else                                 :unread
      end
      {
        user:            latest.user,
        state:           state,
        intent_level:    latest.intent_level,
        mentioned_at:    group.min_by(&:created_at).created_at,
        viewed_at:       latest.viewed_at,
        acknowledged_at: latest.acknowledged_at,
        can_remind:      !cooldown_active?(latest.user_id, viewer.id),
        sla_overdue:     latest.sla_due_at.present? && latest.sla_due_at < Time.current && latest.acknowledged_at.nil?
      }
    end
  end

  # ISS-354 Phase 2 — 24h 리마인드 cooldown.
  # 같은 (sender → receiver) 조합으로 24h 이내 reminded_at 이 set 된 멘션이 있으면 cooldown 활성.
  def cooldown_active?(receiver_id, sender_id)
    notifications.where(notification_type: "mentioned", user_id: receiver_id, sent_by_user_id: sender_id)
                 .where("reminded_at IS NOT NULL AND reminded_at > ?", 24.hours.ago)
                 .exists?
  end
end
