# ISS-293: RFP 첨부파일 자동 분석 Job
# 트리거: new_rfq → make_quo 칸반 이동 시 enqueue
# 결과: 품목별 Task 자동 생성 (또는 폴백 태스크 1개)
module Rfp
  class AnalyzeAttachmentsJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order

      # 첨부파일 없으면 skip
      if order.attachments.none?
        Rails.logger.info("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — 첨부 없음, skip")
        order.update_columns(rfp_analysis_state: "skipped")
        return
      end

      # 24시간 중복 분석 차단
      if order.rfp_analyzed_at && order.rfp_analyzed_at > 24.hours.ago
        Rails.logger.info("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — 24h 내 이미 분석됨, skip")
        return
      end

      order.update_columns(rfp_analysis_state: "processing")

      # ISS-333: 사전 필터 — ariba_login_capture 등 노이즈 제외
      relevant_attachments = order.attachments.select do |att|
        result = Rfp::AttachmentRelevanceFilter.call(att)
        unless result[:relevant]
          Rails.logger.info("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — 첨부 필터 제외: #{att.blob.filename} (#{result[:reason]})")
        end
        result[:relevant]
      end

      if relevant_attachments.empty?
        Rails.logger.info("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — 모든 첨부가 필터에서 제외됨 (login capture 등)")
        create_fallback_task(order, "첨부파일 모두 시스템 자동 캡처(ariba_page 등)로 분류되어 분석 대상 없음. 원본 메일을 직접 확인하세요.")
        order.update_columns(rfp_analysis_state: "skipped", rfp_analyzed_at: Time.current)
        return
      end

      # ISS-334: Ariba 첨부에서 메타데이터 (due_date / owner / event_type) 자동 추출
      enrich_from_ariba(order, relevant_attachments)

      # 1) 텍스트 추출
      extracted = relevant_attachments.map do |att|
        Rfp::AttachmentExtractor.call(att).merge(attachment_id: att.id)
      end
      valid_texts = extracted.select { |e| e[:text].present? }

      if valid_texts.empty?
        Rails.logger.warn("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — 텍스트 추출 실패 (스캔본/미지원 형식)")
        create_fallback_task(order, "첨부파일 텍스트 추출 실패 (스캔본이거나 지원되지 않는 형식)")
        order.update_columns(rfp_analysis_state: "failed", rfp_analyzed_at: Time.current)
        return
      end

      # 2) LLM 분석
      combined = valid_texts.map { |e| "[#{e[:filename]}]\n#{e[:text]}" }.join("\n\n---\n\n")
      result = Rfp::ItemExtractor.call(combined)

      if result.nil? || result["items"].blank?
        Rails.logger.warn("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — LLM 품목 추출 실패")
        create_fallback_task(order, "LLM 품목 추출 실패 또는 문서에서 품목을 인식하지 못함")
        order.update_columns(rfp_analysis_state: "failed", rfp_analyzed_at: Time.current)
        return
      end

      # 3) 태스크 생성
      primary_attachment_id = valid_texts.first[:attachment_id]
      created_count = 0

      result["items"].each do |item|
        # source_excerpt 없거나 너무 짧으면 할루시네이션 의심 — 버림
        next if item["source_excerpt"].blank? || item["source_excerpt"].to_s.length < 10

        order.tasks.create!(
          title: build_task_title(item),
          description: build_task_description(item),
          source_attachment_id: primary_attachment_id,
          source_excerpt: item["source_excerpt"],
          auto_generated: true
        )
        created_count += 1
      end

      if created_count.zero?
        create_fallback_task(order, "품목 추출 완료되었으나 유효한 source_excerpt가 없어 태스크 생성 불가")
        order.update_columns(rfp_analysis_state: "failed", rfp_analyzed_at: Time.current)
      else
        Rails.logger.info("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} — #{created_count}개 태스크 생성 완료")
        order.update_columns(rfp_analysis_state: "done", rfp_analyzed_at: Time.current)
        bump_opus_counter
      end

      # ISS-328: 마감 D-1 긴급 알림
      check_urgent_deadline(order, result)

    rescue => e
      Rails.logger.error("[Rfp::AnalyzeAttachmentsJob] order=#{order_id} #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      begin
        order&.update_columns(rfp_analysis_state: "failed", rfp_analyzed_at: Time.current)
        create_fallback_task(order, "Job 예외: #{e.message}") if order
      rescue => inner
        Rails.logger.error("[Rfp::AnalyzeAttachmentsJob] 폴백 태스크 생성 실패: #{inner.message}")
      end
    end

    private

    # ISS-334: Ariba 첨부 메타데이터 자동 추출 → Order 업데이트
    # 기존 값 보존 (덮어쓰기 안 함). due_date 미설정 + Ariba에서 발견 시에만 채움.
    def enrich_from_ariba(order, attachments)
      ariba_attachment = attachments.find do |att|
        ct = att.blob.content_type.to_s
        fn = att.blob.filename.to_s.downcase
        (ct.include?("html") || fn.end_with?(".doc", ".html", ".htm")) &&
          (fn.match?(/\A\d{10}/) || order.source_type.to_s == "ariba")
      end
      return unless ariba_attachment

      meta = Rfp::AribaPageParser.call(ariba_attachment)
      updates = {}
      updates[:due_date] = meta[:due_date] if meta[:due_date].present? && order.due_date.blank?
      updates[:ariba_event_id] = meta[:ariba_event_id] if meta[:ariba_event_id].present? && order.ariba_event_id.blank?

      if updates.any?
        order.update_columns(updates)
        Rails.logger.info("[Rfp::AribaPageParser] order=#{order.id} enriched: #{updates.inspect}")
      end

      # owner / event_type / commodity는 future Hash field 또는 메모로 저장 가능
      # 현재는 로그만 남기고 추후 컬럼 추가 시 반영
      Rails.logger.info("[Rfp::AribaPageParser] order=#{order.id} parsed meta: owner=#{meta[:owner]} event_type=#{meta[:event_type]} commodity=#{meta[:commodity]}") if meta[:owner].present? || meta[:event_type].present?
    rescue => e
      Rails.logger.warn("[Rfp::AnalyzeAttachmentsJob] enrich_from_ariba error: #{e.message}")
    end

    def create_fallback_task(order, reason)
      order.tasks.create!(
        title: "⚠ 자동 분석 실패 — 수동 입력 필요",
        description: "원인: #{reason}\n\n첨부파일을 직접 확인하여 품목/수량/사양을 수동으로 태스크로 분해하세요.",
        auto_generated: true
      )
    end

    def build_task_title(item)
      name = item["name"].to_s.strip
      qty  = item["quantity"]
      unit = item["unit"].to_s.strip
      qty_str = qty ? " #{qty}#{unit.present? ? unit : ''}" : ""
      "[견적준비] #{name}#{qty_str}"
    end

    def build_task_description(item)
      parts = []
      parts << "품목: #{item['name']}"
      parts << "사양: #{item['spec']}"         if item["spec"].present?
      parts << "수량: #{item['quantity']} #{item['unit']}" if item["quantity"]
      parts << "납기: #{item['delivery_date']}" if item["delivery_date"].present?
      parts << "Material Code: #{item['material_code']}" if item["material_code"].present?
      parts << "Manufacturer: #{item['manufacturer']}"   if item["manufacturer"].present?
      parts << ""
      parts << "[원문 출처]"
      parts << item["source_excerpt"].to_s
      parts.join("\n")
    end

    # ISS-328: rfp_deadline 또는 items의 earliest delivery_date로 D-1 판정
    def check_urgent_deadline(order, result)
      return unless result.is_a?(Hash)

      deadline_str = result["rfp_deadline"].presence ||
                     result["items"].to_a.map { |i| i["delivery_date"] }.compact.min
      return if deadline_str.blank?

      deadline_date = Date.parse(deadline_str.to_s)
      days_left = (deadline_date - Date.current).to_i
      if days_left <= 1 && days_left >= 0
        Rails.logger.info("[Rfp::AnalyzeAttachmentsJob] order=#{order.id} D-#{days_left} 긴급 알림 발송")
        Rfp::UrgentAlertService.call(order, deadline_date, days_left)
      end
    rescue ArgumentError => e
      Rails.logger.warn("[Rfp::AnalyzeAttachmentsJob] deadline parse fail: #{deadline_str} — #{e.message}")
    end

    def bump_opus_counter
      # registry.json의 opus 호출 횟수 트래킹 (간소화 — 실패 시 무시)
      registry_path = Rails.root.join(".claude/issue-db/registry.json")
      return unless File.exist?(registry_path)

      data = JSON.parse(File.read(registry_path))
      budget = data["opus_budget_state"] ||= {}
      budget["daily_calls"] = (budget["daily_calls"].to_i + 1)
      File.write(registry_path, JSON.pretty_generate(data))
    rescue => e
      Rails.logger.debug("[Rfp::AnalyzeAttachmentsJob] bump_opus_counter skip: #{e.message}")
    end
  end
end
