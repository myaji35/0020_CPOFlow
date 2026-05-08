# frozen_string_literal: true

# LAB / RFQ Auto — Order 1개 단위 5단계 파이프라인.
# Phase 1: Step1(첨부 분류) + Step2(품목 + 11항목 누락 체크) 실 구현.
# Phase 2~3: Step3(Task 후보) / Step4(공급사 탐색) / Step5(요약) 골격 + dry-run 결과.
#
# 호출:
#   analysis = RfqAutoAnalysis.create!(order: order, user: user, status: "running", started_at: Time.current)
#   RfqAuto::Analyzer.new(analysis).call
#
# 실행 결과는 analysis.steps (JSON) + summary (JSON) + cost_usd / latency_ms 누적.
# 외부 호출 실패는 단계별로 격리 — 한 단계 실패해도 다음 단계 진행.
module RfqAuto
  class Analyzer
    # "꼭 챙겨야 할 모든 내용" — 11개 도메인 룰 체크리스트
    REQUIRED_FIELDS = %w[
      product_name
      specification
      quantity_unit
      certification
      lead_time
      delivery_address
      incoterms
      payment_terms
      drawing_attached
      client_rfq_no
      validity_period
    ].freeze

    REQUIRED_FIELD_LABELS = {
      "product_name"      => "품명 + 모델번호",
      "specification"     => "사양 (재질/압력/전압 등)",
      "quantity_unit"     => "수량 + 단위",
      "certification"     => "인증 (KS/CE/API/ATEX)",
      "lead_time"         => "요청 납기일",
      "delivery_address"  => "납품지",
      "incoterms"         => "인코텀즈 (FOB/CIF/EXW)",
      "payment_terms"     => "결제조건 (T/T 30d / L/C)",
      "drawing_attached"  => "도면/스펙시트 첨부",
      "client_rfq_no"     => "클라이언트 RFQ 번호",
      "validity_period"   => "견적 유효기간"
    }.freeze

    def initialize(analysis)
      @analysis = analysis
      @order = analysis.order
      @steps_result = {}
      @total_cost = 0.0
      @t0 = Time.current
    end

    def call
      broadcast_progress!  # 시작 시점 — UI에 running 표시

      run_step("step1_attachments") { step1_classify_attachments }
      broadcast_progress!
      run_step("step2_items")       { step2_extract_items }
      broadcast_progress!
      run_step("step3_tasks")       { step3_build_task_candidates }
      broadcast_progress!
      run_step("step4_suppliers")   { step4_find_suppliers }
      broadcast_progress!
      run_step("step5_summary")     { step5_build_summary }

      @analysis.update!(
        status:       "completed",
        steps:        @steps_result.to_json,
        summary:      build_summary_payload.to_json,
        cost_usd:     @total_cost.round(4),
        latency_ms:   ((Time.current - @t0) * 1000).round,
        completed_at: Time.current
      )
      broadcast_progress!  # 최종 — completed 표시
    rescue StandardError => e
      Rails.logger.error "[RfqAuto::Analyzer] FATAL #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      @analysis.update!(
        status:        "failed",
        steps:         @steps_result.to_json,
        error_message: "#{e.class}: #{e.message}",
        latency_ms:    ((Time.current - @t0) * 1000).round,
        completed_at:  Time.current
      )
      broadcast_progress!
    end

    private

    # Turbo Stream 진행률 broadcast — 단계 완료 직후 호출.
    # rfq_auto_analysis_<id> 채널로 partial 부분 갱신 송출.
    # 실패는 silent — 분석 자체를 중단시키지 않음.
    def broadcast_progress!
      # @analysis가 아직 transient steps을 모르므로 in-memory 상태로 임시 partial 렌더
      Turbo::StreamsChannel.broadcast_replace_to(
        "rfq_auto_analysis_#{@analysis.id}",
        target:  "rfq-auto-analysis-#{@analysis.id}",
        partial: "lab/rfq_auto/analysis_card",
        locals:  { analysis: @analysis, transient_steps: @steps_result }
      )
    rescue StandardError => e
      Rails.logger.warn "[RfqAuto::Analyzer] broadcast failed: #{e.class}: #{e.message}"
    end

    # 단계 실행 + 격리. 한 단계 실패해도 결과 채우고 다음 진행.
    def run_step(key)
      step_t0 = Time.current
      result = yield
      result[:latency_ms] = ((Time.current - step_t0) * 1000).round
      result[:status]     ||= "ok"
      @steps_result[key]   = result
    rescue StandardError => e
      Rails.logger.warn "[RfqAuto::Analyzer] step #{key} failed: #{e.class}: #{e.message}"
      @steps_result[key] = {
        status:     "error",
        error:      "#{e.class}: #{e.message}",
        latency_ms: ((Time.current - step_t0) * 1000).round
      }
    end

    # ── Step 1 — 첨부 파일 인식 + 견적 관련도 분류 ───────────────
    def step1_classify_attachments
      return { status: "skipped", reason: "no attachments", items: [] } unless @order.attachments.any?

      classified = @order.attachments.map do |att|
        cls = Rfp::AttachmentClassifier.call(att) rescue { type: "other", confidence: 0.0, source: "error" }
        {
          filename:   att.blob.filename.to_s,
          byte_size:  att.blob.byte_size,
          content_type: att.blob.content_type,
          type:       cls[:type],
          confidence: cls[:confidence],
          source:     cls[:source],
          relevance_score: relevance_score_for(cls[:type], cls[:confidence])
        }
      end

      relevant_count = classified.count { |c| c[:relevance_score] >= 60 }
      { items: classified, total: classified.size, relevant: relevant_count }
    end

    def relevance_score_for(type, confidence)
      base = case type
             when "rfq", "quotation"          then 95
             when "po", "invoice"             then 70
             when "delivery_note", "grn"      then 40
             when "packing_list"              then 50
             else 20
             end
      (base * (confidence || 0.5)).round
    end

    # ── Step 2 — 품목 + 11항목 누락 체크 ──────────────────────────
    def step2_extract_items
      combined_text = build_combined_text
      return { status: "skipped", reason: "no extractable text", items: [] } if combined_text.blank?

      raw = Rfp::ItemExtractor.call(combined_text) rescue nil
      items = (raw.is_a?(Hash) ? raw[:items] : raw) || []

      enriched = items.map.with_index do |item, idx|
        missing = check_required_fields(item, combined_text)
        {
          idx: idx + 1,
          name:           pick(item, :name, :product_name, :item_name),
          model:          pick(item, :model, :model_no, :part_no),
          spec:           pick(item, :spec, :specification, :description),
          quantity:       pick(item, :quantity, :qty),
          unit:           pick(item, :unit, :uom),
          certification:  pick(item, :certification, :cert),
          missing_fields: missing,
          missing_count:  missing.size,
          confidence:     pick(item, :confidence) || 0.7
        }
      end

      { items: enriched, count: enriched.size }
    end

    def build_combined_text
      texts = []
      @order.attachments.each do |att|
        next unless att.blob.byte_size.to_i < 10.megabytes
        text = Rfp::AttachmentExtractor.new(att).call rescue nil
        texts << text if text.present?
      end
      texts << @order.original_email_body if @order.original_email_body.present?
      texts.compact.join("\n\n---\n\n")
    end

    def check_required_fields(item, full_text)
      missing = []
      REQUIRED_FIELDS.each do |field|
        case field
        when "product_name"      then missing << field if pick(item, :name, :product_name).blank?
        when "specification"     then missing << field if pick(item, :spec, :specification).blank?
        when "quantity_unit"     then missing << field if pick(item, :quantity, :qty).blank? || pick(item, :unit, :uom).blank?
        when "certification"     then missing << field if pick(item, :certification, :cert).blank? && !full_text.match?(/(KS|CE|API|ATEX|ISO)\b/i)
        when "lead_time"         then missing << field unless full_text.match?(/(lead\s*time|delivery\s*date|by\s+\d|due|납기)/i)
        when "delivery_address"  then missing << field unless full_text.match?(/(delivery\s*address|ship\s*to|destination|납품지)/i)
        when "incoterms"         then missing << field unless full_text.match?(/(FOB|CIF|EXW|DDP|FCA|CFR)\b/i)
        when "payment_terms"     then missing << field unless full_text.match?(/(payment|T\/T|L\/C|net\s*\d|결제)/i)
        when "drawing_attached"  then missing << field unless @order.attachments.any? { |a| a.blob.filename.to_s.match?(/\.(pdf|dwg|dxf|step|stp|igs|png|jpg|jpeg)$/i) }
        when "client_rfq_no"     then missing << field if @order.reference_no.blank? && @order.rfq_no.blank?
        when "validity_period"   then missing << field unless full_text.match?(/(valid|expir|유효)/i)
        end
      end
      missing
    end

    def pick(hash, *keys)
      return nil unless hash.is_a?(Hash)
      keys.each do |k|
        v = hash[k] || hash[k.to_s]
        return v if v.present?
      end
      nil
    end

    # ── Step 3 — Task 후보 (dry-run, 저장 안 함) ─────────────────
    def step3_build_task_candidates
      items = @steps_result.dig("step2_items", :items) || []
      return { status: "skipped", reason: "no items", tasks: [] } if items.empty?

      tasks = items.flat_map do |item|
        # 품목 1개 → 11항목 체크리스트 task
        REQUIRED_FIELDS.map do |field|
          {
            item_idx: item[:idx],
            item_name: item[:name],
            field: field,
            label: REQUIRED_FIELD_LABELS[field],
            status: item[:missing_fields].include?(field) ? "missing" : "ok"
          }
        end
      end

      { tasks: tasks, count: tasks.size, missing_count: tasks.count { |t| t[:status] == "missing" } }
    end

    # ── Step 4 — 공급사 탐색 (Phase 1: 자체 Supplier DB만) ──────
    def step4_find_suppliers
      items = @steps_result.dig("step2_items", :items) || []
      return { status: "skipped", reason: "no items", suppliers: [] } if items.empty?

      candidates = items.first(3).flat_map do |item|
        keyword = item[:name].to_s
        next [] if keyword.blank?

        local = Supplier.where("name LIKE ? OR ecount_code LIKE ?", "%#{keyword}%", "%#{keyword}%").limit(5).map do |s|
          {
            source:        "local_db",
            confidence:    90,
            name:          s.name,
            email:         s.try(:email),
            phone:         s.try(:phone),
            website:       s.try(:website),
            country:       s.try(:country),
            item_keyword:  keyword
          }
        end

        local
      end

      { suppliers: candidates, count: candidates.size, sources: candidates.map { |c| c[:source] }.tally }
    end

    # ── Step 5 — 종합 보고서 ─────────────────────────────────────
    def step5_build_summary
      build_summary_payload
    end

    def build_summary_payload
      step1 = @steps_result["step1_attachments"] || {}
      step2 = @steps_result["step2_items"] || {}
      step3 = @steps_result["step3_tasks"] || {}
      step4 = @steps_result["step4_suppliers"] || {}

      {
        attachments_total:    step1[:total] || 0,
        attachments_relevant: step1[:relevant] || 0,
        items_count:          step2[:count] || 0,
        items_missing_total:  (step2[:items] || []).sum { |i| i[:missing_count].to_i },
        tasks_total:          step3[:count] || 0,
        tasks_missing:        step3[:missing_count] || 0,
        suppliers_total:      step4[:count] || 0,
        cost_usd:             @total_cost.round(4),
        elapsed_seconds:      (Time.current - @t0).round(2)
      }
    end
  end
end
