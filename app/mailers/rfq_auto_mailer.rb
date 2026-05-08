# frozen_string_literal: true

# LAB / RFQ Auto D-6 — 선택된 공급사들에게 RFQ 견적 요청 이메일 발송.
class RfqAutoMailer < ApplicationMailer
  default from: ENV.fetch("RFQ_FROM_EMAIL", "no-reply@cpoflow.ddtl.co.kr")

  # 호출:
  #   RfqAutoMailer.with(
  #     selection: rfq_auto_supplier_selection,
  #     order: order,
  #     items: [{name:, spec:, quantity:, unit:}, ...],
  #     attachments_data: [{filename:, content_type:, body:}, ...]
  #   ).rfq_inquiry.deliver_later
  def rfq_inquiry
    @selection = params[:selection]
    @order     = params[:order]
    @items     = params[:items] || []
    @from_user = params[:from_user]

    # 첨부파일 attach
    Array(params[:attachments_data]).each do |att|
      attachments[att[:filename].to_s] = { mime_type: att[:content_type], content: att[:body] }
    end

    to_email = @selection.contact_email
    return if to_email.blank?

    subject_text = "[RFQ] #{@order.reference_no.presence || @order.title.to_s.truncate(60)} — Quotation Request"

    mail(
      to:      to_email,
      subject: subject_text,
      reply_to: @from_user&.email
    )
  end
end
