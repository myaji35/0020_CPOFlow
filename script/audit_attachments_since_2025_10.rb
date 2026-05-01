since = Time.zone.local(2025, 10, 1)
puts "=== 2025-10-01 이후 첨부 전수 검수 ==="

total = Order.where("created_at >= ?", since).count
puts "total_orders_since: #{total}"

ariba_missing = Order.where("created_at >= ?", since)
  .where("sap_portal_links LIKE ?", "%ariba.com%")
  .left_joins(attachments_attachments: :blob)
  .where(active_storage_blobs: { id: nil }).distinct.count
puts "ariba_links_but_no_attachment: #{ariba_missing}"

linked_missing = 0
linked_total = 0
Order.where("created_at >= ?", since)
  .where.not(linked_files: [ nil, "" ])
  .find_each(batch_size: 500) do |o|
    links = (JSON.parse(o.linked_files.to_s) rescue [])
    next unless links.any?
    linked_total += 1
    linked_missing += 1 if o.attachments.blank?
  end
puts "orders_with_linked_files: #{linked_total}"
puts "linked_files_but_no_attachment: #{linked_missing}"

no_attach = Order.where("created_at >= ?", since)
  .left_joins(attachments_attachments: :blob)
  .where(active_storage_blobs: { id: nil }).distinct.count
puts "orders_with_zero_attachments: #{no_attach}"

# original_email_html_body에 첨부/Ariba 흔적이 있는데 저장 안 된 것 집계
has_email_body = Order.where("created_at >= ?", since)
  .where.not(original_email_html_body: [ nil, "" ]).count
puts "orders_with_email_body: #{has_email_body}"
