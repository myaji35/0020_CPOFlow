# frozen_string_literal: true

# 첨부 1개당 분석 1회 단위로 Sonnet 4.6 vision 호출.
# 실패해도 다른 첨부 분석에는 영향 없음.
# Turbo Stream broadcast로 첨부 배지 + 품목 탭 자동 갱신.
class QuoteAttachmentAnalyzeJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    aqa = AttachmentQuoteAnalysis.find(analysis_id)
    aqa.update!(status: "running", started_at: Time.current)
    broadcast_badge(aqa)

    result = QuoteItemExtractor.new(aqa.active_storage_attachment).call

    items = result[:items]
    aqa.update!(
      status: "completed",
      is_quote_doc: items.any?,
      items_json: items.to_json,
      llm_model: result[:llm_model],
      cost_usd: result[:cost_usd],
      latency_ms: result[:latency_ms],
      completed_at: Time.current
    )
    seed_items(aqa, items) if items.any?
    broadcast_badge(aqa)
    broadcast_items_frame(aqa.order)
  rescue QuoteItemExtractor::AnthropicCreditError, QuoteItemExtractor::ExtractionError, StandardError => e
    aqa = AttachmentQuoteAnalysis.find_by(id: analysis_id)
    return unless aqa
    aqa.update!(
      status: "failed",
      error_message: "#{e.class.name.demodulize}: #{e.message}",
      completed_at: Time.current
    )
    broadcast_badge(aqa)
  end

  private

  # 시드 정책: 새 분석 결과를 max(row_no)+1부터 순차 append.
  # 기존 행(사용자 편집 포함)은 절대 update/delete 하지 않음.
  # 따라서 같은 첨부를 재분석하면 행이 중복될 수 있음 — 이는 의도적이며,
  # 사용자가 [-] 버튼으로 불필요 행을 삭제하도록 위임.
  def seed_items(aqa, items)
    next_row = (aqa.order.quote_items.maximum(:row_no) || 0) + 1
    items.each_with_index do |raw, idx|
      OrderQuoteItem.create!(
        order: aqa.order,
        source_attachment_id: aqa.active_storage_attachment_id,
        row_no: next_row + idx,
        item: raw["item"].to_s.presence,
        description: raw["description"],
        model_part_no: raw["model_part_no"],
        manufacturer_brand: raw["manufacturer_brand"],
        unit: raw["unit"],
        qty: parse_qty(raw["qty"]),
        remarks: raw["remarks"]
      )
    end
  end

  def parse_qty(raw)
    return nil if raw.blank?
    str = raw.to_s.scan(/[\d.]+/).first
    return nil if str.blank?
    BigDecimal(str)
  rescue ArgumentError
    nil
  end

  def broadcast_badge(aqa)
    Turbo::StreamsChannel.broadcast_replace_to(
      "order-#{aqa.order_id}",
      target: "quote-attachment-badge-#{aqa.active_storage_attachment_id}",
      partial: "orders/quote_attachment_badge",
      locals: { order: aqa.order, attachment: aqa.active_storage_attachment, aqa: aqa }
    )
  rescue StandardError => e
    Rails.logger.warn "[QuoteAttachmentAnalyzeJob] broadcast_badge failed: #{e.message}"
  end

  def broadcast_items_frame(order)
    Turbo::StreamsChannel.broadcast_replace_to(
      "order-#{order.id}",
      target: "quote-items-frame-#{order.id}",
      partial: "orders/quote_items_frame",
      locals: {
        order: order,
        items: order.quote_items.ordered,
        sources: AttachmentQuoteAnalysis.where(order_id: order.id, status: "completed")
                                          .includes(:active_storage_attachment)
      }
    )
  rescue StandardError => e
    Rails.logger.warn "[QuoteAttachmentAnalyzeJob] broadcast_items_frame failed: #{e.message}"
  end
end
