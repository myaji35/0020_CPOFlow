class TrackingNumber < ApplicationRecord
  belongs_to :order
  belongs_to :tracking_code

  validates :value, presence: true
  validates :tracking_code_id, uniqueness: { scope: :order_id }

  # 레거시 컬럼 거울 쓰기: RFQ/QUO/PO 코드는 orders.rfq_no/quo_no/po_no 와 동기화
  # → 이메일 파서·검색·기존 라우트 호환을 위해 유지 (추후 제거)
  LEGACY_FIELD_MAP = {
    "RFQ" => :rfq_no,
    "QUO" => :quo_no,
    "PO"  => :po_no
  }.freeze

  after_save    :sync_legacy_column
  after_destroy :clear_legacy_column

  private

  def sync_legacy_column
    field = LEGACY_FIELD_MAP[tracking_code.code]
    return unless field
    return if order.send(field) == value
    order.update_column(field, value)
  end

  def clear_legacy_column
    field = LEGACY_FIELD_MAP[tracking_code&.code]
    return unless field
    order.update_column(field, nil)
  end
end
