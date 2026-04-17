class Activity < ApplicationRecord
  belongs_to :order
  belongs_to :user

  scope :recent, -> { order(created_at: :desc) }
  scope :field_changes, -> { where(action: "field_changed") }

  # ISS-203: 필드 라벨 매핑
  FIELD_LABELS = {
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
    "title"             => "제목"
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
    when "supplier_id" then Supplier.find_by(id: raw)&.name || "##{raw}"
    when "client_id"   then Client.find_by(id: raw)&.name   || "##{raw}"
    when "project_id"  then Project.find_by(id: raw)&.name  || "##{raw}"
    else raw.to_s
    end
  end

  def from_label
    Order::STATUS_LABELS[Order.statuses.key(from_status)] if from_status
  end

  def to_label
    Order::STATUS_LABELS[Order.statuses.key(to_status)] if to_status
  end
end
