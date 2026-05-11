# frozen_string_literal: true

class AttachmentQuoteAnalysesController < ApplicationController
  before_action :authenticate_user!

  # POST /attachment_quote_analyses — params[:attachment_id]
  def create
    attachment = ActiveStorage::Attachment.find(params[:attachment_id])
    order = attachment.record
    return head :forbidden unless order.is_a?(Order) && member_or_above?

    aqa = AttachmentQuoteAnalysis.find_or_initialize_by(active_storage_attachment_id: attachment.id)
    aqa.assign_attributes(order: order, status: "pending", error_message: nil)
    aqa.save!

    QuoteAttachmentAnalyzeJob.perform_later(aqa.id)

    render turbo_stream: turbo_stream.replace(
      "quote-attachment-badge-#{attachment.id}",
      partial: "orders/quote_attachment_badge",
      locals: { order: order, attachment: attachment, aqa: aqa }
    )
  end

  # 정책 (MVP): 재분석은 새 결과를 OrderQuoteItem에 append.
  # 기존 사용자 편집 행(user_edited: true)은 그대로 보존.
  # 충돌 모달(기존 유지/교체/병합)은 P5+ 향후 작업 (spec §6, §14).
  # POST /attachment_quote_analyses/:id/reanalyze
  def reanalyze
    aqa = AttachmentQuoteAnalysis.find(params[:id])
    return head :forbidden unless member_or_above?

    aqa.increment!(:reanalyzed_count)
    aqa.update!(status: "pending", error_message: nil)
    QuoteAttachmentAnalyzeJob.perform_later(aqa.id)

    render turbo_stream: turbo_stream.replace(
      "quote-attachment-badge-#{aqa.active_storage_attachment_id}",
      partial: "orders/quote_attachment_badge",
      locals: { order: aqa.order, attachment: aqa.active_storage_attachment, aqa: aqa }
    )
  end

  private

  def member_or_above?
    %w[member manager admin].include?(current_user.role.to_s)
  end
end
