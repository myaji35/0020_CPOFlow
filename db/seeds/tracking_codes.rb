# 기본 관리번호 코드 시드 + 기존 컬럼(rfq_no/quo_no/po_no) 데이터를 신규 구조로 백필
defaults = [
  { code: "RFQ", short_label: "R", name: "Request for Quotation", color: "#6366F1", position: 1 },
  { code: "QUO", short_label: "Q", name: "Quotation",             color: "#F59E0B", position: 2 },
  { code: "PO",  short_label: "P", name: "Purchase Order",        color: "#10B981", position: 3 }
]

defaults.each do |attrs|
  tc = TrackingCode.find_or_initialize_by(code: attrs[:code])
  tc.assign_attributes(attrs.merge(active: true))
  tc.save!
end

puts "  TrackingCode: #{TrackingCode.count}개 등록"

# 기존 데이터 백필 — orders.rfq_no/quo_no/po_no → tracking_numbers
{
  "RFQ" => :rfq_no,
  "QUO" => :quo_no,
  "PO"  => :po_no
}.each do |code, field|
  tc = TrackingCode.find_by(code: code)
  next unless tc
  count = 0
  Order.where.not(field => [ nil, "" ]).find_each do |o|
    val = o.send(field)
    next if val.blank?
    tn = TrackingNumber.find_or_initialize_by(order_id: o.id, tracking_code_id: tc.id)
    next if tn.persisted? && tn.value == val  # 변경 없음
    tn.value = val
    # 콜백 sync_legacy_column 회피 (이미 컬럼 값 사용 중)
    tn.save!(validate: true) && (count += 1)
  end
  puts "  #{code}: #{count}건 백필"
end
