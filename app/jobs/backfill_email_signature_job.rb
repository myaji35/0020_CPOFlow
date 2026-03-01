class BackfillEmailSignatureJob < ApplicationJob
  queue_as :default

  # 기존 Order 중 email_signature_json이 없고 original_email_body가 있는 건 재파싱
  def perform(batch_size: 100)
    orders = Order.where(email_signature_json: nil)
                  .where.not(original_email_body: [ nil, "" ])
                  .limit(batch_size)

    updated = 0
    orders.find_each do |order|
      result = Gmail::EmailSignatureParserService.parse(
        order.original_email_body,
        order.original_email_html_body
      )
      next if result.blank?

      order.update_column(:email_signature_json, result.to_json)
      updated += 1
    rescue => e
      Rails.logger.warn "[BackfillEmailSignature] Order ##{order.id} failed: #{e.message}"
    end

    Rails.logger.info "[BackfillEmailSignature] Processed #{orders.size} orders, updated #{updated}"
  end
end
