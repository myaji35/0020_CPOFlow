# frozen_string_literal: true

# Ariba 포털에서 문서를 자동 수집하는 백그라운드 잡
# EmailSyncJob에서 Ariba 링크가 포함된 Order 생성 시 자동으로 큐잉됨
#
# Manual trigger: AribaFetchJob.perform_later(order_id: 42)
class AribaFetchJob < ApplicationJob
  queue_as :default

  # Ariba 포털 응답이 느릴 수 있으므로 넉넉한 재시도 간격
  retry_on StandardError, wait: 10.minutes, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(order_id:, force: false)
    order = Order.find(order_id)

    # 자동 수집(EmailSyncJob) 시에만 중복 체크, 수동 수집(버튼)은 force=true
    unless force
      if order.attachments.any? { |a| a.filename.to_s.match?(/ariba_page_/i) }
        Rails.logger.info "[AribaFetchJob] Order##{order.id}: Ariba 문서 이미 존재, 스킵"
        return
      end
    end

    Rails.logger.info "[AribaFetchJob] Order##{order.id}: Ariba 문서 자동 수집 시작"

    result = Sap::AribaScraperService.new.fetch_pdfs_for_order(order)

    if result[:saved].any?
      Rails.logger.info "[AribaFetchJob] Order##{order.id}: #{result[:saved].size}개 문서 저장 완료"
    end

    if result[:errors].any?
      Rails.logger.warn "[AribaFetchJob] Order##{order.id}: 오류 #{result[:errors].join(', ')}"
    end
  end
end
