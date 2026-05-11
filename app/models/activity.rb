class Activity < ApplicationRecord
  # ISS-203: Order 감사 로그 (legacy 경로 — order_id 컬럼).
  # ISS-303: Employee/Visa/EmploymentContract/Certification 등 HR 모델로 확장 (polymorphic 경로).
  belongs_to :order, optional: true
  belongs_to :auditable, polymorphic: true, optional: true
  belongs_to :user

  scope :recent, -> { order(created_at: :desc) }
  scope :field_changes, -> { where(action: "field_changed") }

  # ISS-203 + ISS-303: 필드 라벨 매핑 (Order + HR 도메인)
  FIELD_LABELS = {
    # Order
    "estimated_value"   => "예상금액",
    "quantity"          => "수량",
    "currency"          => "통화",
    "due_date"          => "납기일",
    "supplier_id"       => "공급사",
    "client_id"         => "발주처",
    "project_id"        => "현장",
    "po_no"             => "PO 번호",
    "rfq_no"            => "RFQ 번호",
    "quo_no"            => "견적 번호",
    "payment_terms"     => "결제조건",
    "delivery_location" => "납품지",
    "item_name"         => "품목명",
    "title"             => "제목",
    # Employee
    "name"              => "이름",
    "name_en"           => "영문 이름",
    "email"             => "이메일",
    "phone"             => "전화번호",
    "nationality"       => "국적",
    "employment_type"   => "고용형태",
    "department_id"     => "부서",
    "department"        => "부서명(legacy)",
    "job_title"         => "직책",
    "hire_date"         => "입사일",
    "termination_date"  => "퇴직일",
    "passport_number"   => "여권번호",
    "active"            => "재직 여부",
    # Visa
    "visa_type"         => "비자 유형",
    "visa_number"       => "비자 번호",
    "issuing_country"   => "발급국",
    "issue_date"        => "발급일",
    "expiry_date"       => "만료일",
    "status"            => "상태",
    # EmploymentContract
    "start_date"        => "계약 시작일",
    "end_date"          => "계약 종료일",
    "base_salary"       => "기본급",
    "currency"          => "통화",
    "pay_frequency"     => "급여 주기",
    "project_id"        => "현장",
    # Certification
    "issued_date"       => "발급일",
    "issuing_body"      => "발급기관"
  }.freeze

  def status_changed?
    from_status.present? && to_status.present?
  end

  def field_changed?
    action == "field_changed" && field.present?
  end

  def field_label
    FIELD_LABELS[field.to_s] || field.to_s.humanize
  end

  def display_value(raw)
    return "—" if raw.blank?
    case field
    when "supplier_id"   then Supplier.find_by(id: raw)&.name || "##{raw}"
    when "client_id"     then Client.find_by(id: raw)&.name   || "##{raw}"
    when "project_id"    then Project.find_by(id: raw)&.name  || "##{raw}"
    when "department_id" then Department.find_by(id: raw)&.name || "##{raw}"
    when "job_title_id"  then JobTitle.find_by(id: raw)&.name  || "##{raw}"
    when "manager_id"    then Employee.find_by(id: raw)&.name  || "##{raw}"
    else raw.to_s
    end
  end

  def from_label
    Order::STATUS_LABELS[Order.statuses.key(from_status)] if from_status
  end

  def to_label
    Order::STATUS_LABELS[Order.statuses.key(to_status)] if to_status
  end

  # ISS-303: HR 타임라인에서 액션 한국어 라벨
  ACTION_LABELS = {
    "created"       => "등록됨",
    "updated"       => "수정됨",
    "destroyed"     => "삭제됨",
    "field_changed" => "필드 변경"
  }.freeze

  def action_label
    ACTION_LABELS[action.to_s] || action.to_s
  end
end
