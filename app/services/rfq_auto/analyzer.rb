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
      # run_step이 시작/완료 시점에 자동 broadcast하므로 외부 broadcast 호출은 시작/종료에만.
      broadcast_progress!  # 시작 시점 — 모든 단계 pending 상태로 표시

      run_step("step1_attachments") { step1_classify_attachments }
      run_step("step1b_format")     { step1b_format_match }
      run_step("step2_items")       { step2_extract_items }
      run_step("step3_tasks")       { step3_build_task_candidates }
      run_step("step4_suppliers")   { step4_find_suppliers }
      run_step("step5_summary")     { step5_build_summary }

      @analysis.update!(
        status:       "completed",
        steps:        @steps_result.to_json,
        summary:      build_summary_payload.to_json,
        cost_usd:     @total_cost.round(4),
        latency_ms:   ((Time.current - @t0) * 1000).round,
        completed_at: Time.current
      )
      broadcast_progress!  # 최종 — completed 상태 + 메트릭 카드 표시
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
    # 시작 시점에 'running' 마커 broadcast → 사용자에게 '이 단계 처리 중' 시각화.
    def run_step(key)
      step_t0 = Time.current
      @steps_result[key] = { status: "running", started_at: step_t0.iso8601 }
      broadcast_progress!  # 단계 시작 알림 — UI 스피너 표시

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

    # ── Step 1b — 양식 패턴 매칭 (Phase 2-A: NAWAH/ENEC Ariba 정규식 라이브러리) ──
    # 첨부 결합 텍스트에 대해 FormatMatcher로 양식 식별 + 헤더 필드 + MUST/NICE 추출.
    # Step 2(LLM) 진입 전 1차 추출 — 정규식만으로 NAWAH/ENEC 82% 커버.
    # @format_match_result에 저장 → 후속 단계가 "이건 무효 Ariba 로그인" 같은 신호 활용.
    def step1b_format_match
      combined_text = build_combined_text
      @format_match_result = nil

      if combined_text.blank? || combined_text.length < 100
        return { status: "skipped", reason: "text too short", text_chars: combined_text.to_s.length }
      end

      matcher = RfqAuto::FormatMatcher.new(combined_text)
      summary = matcher.summary

      @format_match_result = {
        format:           summary[:format],
        invalid:          summary[:invalid],
        fields:           matcher.fields,
        must_comply:      matcher.must_comply,
        nice_to_have:     matcher.nice_to_have,
        critical_count:   summary[:critical_count],
        must_count:       summary[:must_count],
        nice_count:       summary[:nice_count]
      }

      {
        format:         summary[:format] || "(unknown)",
        invalid:        summary[:invalid],
        fields_count:   matcher.fields.size,
        must_comply:    matcher.must_comply.map { |m| { category: m[:category], severity: m[:severity] } },
        nice_to_have:   matcher.nice_to_have.map { |n| n[:type] },
        critical_count: summary[:critical_count]
      }
    end

    # ── Step 2 — 품목 + 11항목 누락 체크 (Phase 4: A+C 적용) ───────
    # 흐름:
    #   1. 텍스트 추출 (build_combined_text — pdf/docx/.doc/xlsx/html/txt)
    #   2. 텍스트 < 50자면 OCR fallback 시도 (자체 서버 tesseract, 무료)
    #   3. ItemExtractor (Sonnet 4.6) 호출 → 비용/토큰 누적
    #   4. 0건이면 Opus 4.7 escalate 1회 (RFP_ITEM_MODEL=claude-opus-4-7 임시 override)
    #   5. 그래도 0건 + PDF/이미지 첨부 있으면 Vision 폴백 (Sonnet)
    def step2_extract_items
      combined_text = build_combined_text
      text_chars    = combined_text.to_s.length

      # OCR 폴백 — 텍스트 < 50자이고 OCR 가능 첨부가 있을 때
      ocr_used = false
      if text_chars < 50 && @order.attachments.any? { |a| a.blob.filename.to_s.match?(/\.(pdf|png|jpg|jpeg|tiff|bmp)$/i) }
        ocr_text = RfqAuto::OcrTextExtractor.new(@order, max_pages: 5).call rescue nil
        if ocr_text.present? && ocr_text.length > 50
          combined_text = "#{combined_text}\n\n=== OCR 추출 ===\n#{ocr_text}"
          text_chars = combined_text.length
          ocr_used = true
          Rails.logger.info "[RfqAuto::Analyzer] OCR 폴백 성공: #{ocr_text.length}자 추출"
        end
      end

      text_preview = combined_text.to_s.strip[0, 2000]

      if combined_text.blank?
        return { status: "skipped", reason: "텍스트 추출 실패 — OCR 미설치 또는 인식 불가", items: [],
                 text_preview: nil, text_chars: 0, doc_level_missing: REQUIRED_FIELDS.dup,
                 doc_level_missing_labels: REQUIRED_FIELDS.map { |f| REQUIRED_FIELD_LABELS[f] },
                 ocr_used: ocr_used, vision_used: false }
      end

      # 1차 ItemExtractor (Haiku 4.5 기본 — Step 1b 결과를 컨텍스트로 주입)
      llm_error = nil
      raw = run_item_extractor(combined_text, format_context: @format_match_result) { |err| llm_error = err }
      items = (raw.is_a?(Hash) ? raw["items"] : nil) || []
      llm_cost = raw.is_a?(Hash) ? raw["_cost_usd"].to_f : 0.0
      llm_model = raw.is_a?(Hash) ? raw["_model"] : nil
      @total_cost += llm_cost

      # Sonnet escalation — Haiku가 0건이면 Sonnet으로 1회 재시도 (Opus는 너무 비쌈, 양식 컨텍스트 있으면 Sonnet으로 충분)
      escalated = false
      escalation_cost = 0.0
      if items.empty? && llm_error.nil? && combined_text.length >= 50
        ENV["RFP_ITEM_MODEL"] = "claude-sonnet-4-6"
        begin
          retry_raw = run_item_extractor(combined_text, format_context: @format_match_result) { |err| llm_error = err }
          if retry_raw.is_a?(Hash) && retry_raw["items"].is_a?(Array) && retry_raw["items"].any?
            items = retry_raw["items"]
            escalated = true
            escalation_cost = retry_raw["_cost_usd"].to_f
            llm_model = retry_raw["_model"]
            @total_cost += escalation_cost
            Rails.logger.info "[RfqAuto::Analyzer] Sonnet escalation 성공: #{items.size}품 cost=$#{escalation_cost}"
          end
        ensure
          ENV.delete("RFP_ITEM_MODEL")
        end
      end

      # Vision 폴백 — 그래도 0건 + 이미지/PDF 첨부 있을 때
      vision_used = false
      vision_cost = 0.0
      vision_pages = 0
      vision_model = nil
      vision_error = nil
      if items.empty? && @order.attachments.any? { |a| a.blob.filename.to_s.match?(/\.(pdf|png|jpg|jpeg|webp)$/i) }
        begin
          vresult = RfqAuto::VisionItemExtractor.new(@order, pages_cap: 5).call
          items        = vresult[:items] || []
          vision_used  = true
          vision_cost  = vresult[:cost_usd].to_f
          vision_pages = vresult[:page_count].to_i
          vision_model = vresult[:model]
          @total_cost += vision_cost
          Rails.logger.info "[RfqAuto::Analyzer] Vision 폴백 결과 items=#{items.size} cost=$#{vision_cost} pages=#{vision_pages}"
        rescue RfqAuto::VisionItemExtractor::AnthropicCreditError => e
          vision_error = "❗ Anthropic API 잔액 부족 — 충전 후 재시도 부탁드립니다 (#{e.message.truncate(120)})"
          Rails.logger.warn "[RfqAuto::Analyzer] #{vision_error}"
        rescue StandardError => e
          vision_error = "#{e.class}: #{e.message.truncate(160)}"
          Rails.logger.warn "[RfqAuto::Analyzer] Vision 폴백 실패: #{vision_error}"
        end
      end

      enriched = items.map.with_index do |item, idx|
        missing = check_required_fields(item, combined_text)
        excerpt = pick(item, :source_excerpt, :source, :evidence).to_s
        {
          idx: idx + 1,
          name:           pick(item, :name, :product_name, :item_name),
          model:          pick(item, :model, :model_no),
          spec:           pick(item, :spec, :specification, :description),
          quantity:       pick(item, :quantity, :qty),
          unit:           pick(item, :unit, :uom),
          certification:  pick(item, :certification, :cert),
          # ISS-358 Wave 0 (T0c): AtoZ RFQ 양식 7컬럼용 — extractor가 추출한 4개 키 통과
          manufacturer:   pick(item, :manufacturer, :maker),
          brand:          pick(item, :brand),
          part_no:        pick(item, :part_no, :part_number, :sku),
          remarks:        pick(item, :remarks, :notes, :note),
          source_file:    find_source_file(excerpt),
          source_excerpt: excerpt[0, 160],
          missing_fields: missing,
          missing_count:  missing.size,
          confidence:     pick(item, :confidence) || 0.7
        }
      end

      # 품목 0개라도 문서 전체 기준 11항목 점검 (텍스트만 검사하는 항목들)
      doc_missing = REQUIRED_FIELDS.select do |field|
        case field
        when "certification"     then !combined_text.match?(/(KS|CE|API|ATEX|ISO)\b/i)
        when "lead_time"         then !combined_text.match?(/(lead\s*time|delivery\s*date|by\s+\d|due|납기)/i)
        when "delivery_address"  then !combined_text.match?(/(delivery\s*address|ship\s*to|destination|납품지)/i)
        when "incoterms"         then !combined_text.match?(/(FOB|CIF|EXW|DDP|FCA|CFR)\b/i)
        when "payment_terms"     then !combined_text.match?(/(payment|T\/T|L\/C|net\s*\d|결제)/i)
        when "drawing_attached"  then !@order.attachments.any? { |a| a.blob.filename.to_s.match?(/\.(pdf|dwg|dxf|step|stp|igs|png|jpg|jpeg)$/i) }
        when "client_rfq_no"     then @order.reference_no.blank? && @order.rfq_no.blank?
        when "validity_period"   then !combined_text.match?(/(valid|expir|유효)/i)
        # 품목 단위 항목들 — 품목 0개면 결정적으로 누락
        when "product_name", "specification", "quantity_unit"
          enriched.empty? || enriched.all? { |e| e[:missing_fields].include?(field) }
        end
      end

      {
        items:                    enriched,
        count:                    enriched.size,
        text_chars:               text_chars,
        text_preview:             text_preview,
        llm_error:                llm_error,
        llm_model:                llm_model,
        llm_cost_usd:             llm_cost.round(4),
        doc_level_missing:        doc_missing,
        doc_level_missing_labels: doc_missing.map { |f| REQUIRED_FIELD_LABELS[f] },
        ocr_used:                 ocr_used,
        # Opus escalation 메타
        escalated:                escalated,
        escalation_cost_usd:      escalation_cost.round(4),
        # Vision 폴백 메타 정보
        vision_used:              vision_used,
        vision_cost_usd:          vision_cost,
        vision_pages:             vision_pages,
        vision_model:             vision_model,
        vision_error:             vision_error
      }
    end

    # ItemExtractor 호출 + 예외 격리 — 잔액 부족은 위로 전파.
    # @param format_context [Hash, nil] FormatMatcher 결과 — 헤더/MUST 사전 인식 시 LLM에 컨텍스트로 주입.
    def run_item_extractor(text, format_context: nil)
      result = Rfp::ItemExtractor.call(text, format_context: format_context)
      result
    rescue StandardError => e
      msg = "#{e.class}: #{e.message}"
      Rails.logger.warn "[RfqAuto::Analyzer] ItemExtractor 실패: #{msg}"
      yield(msg) if block_given?
      raise if e.message.to_s.include?("잔액 부족")
      nil
    end

    # 파일별 마커를 삽입한 결합 텍스트 생성. 각 chunk는 [SOURCE: filename] ... [END SOURCE] 형식.
    # @file_chunks에 [{filename:, text:}] 인덱스 저장 → source_excerpt → 파일명 매칭에 사용.
    def build_combined_text
      @file_chunks = []
      texts = []
      @order.attachments.each do |att|
        next unless att.blob.byte_size.to_i < 10.megabytes
        result = Rfp::AttachmentExtractor.new(att).call rescue nil
        text = result.is_a?(Hash) ? result[:text] : result
        next unless text.present?
        filename = att.blob.filename.to_s
        @file_chunks << { filename: filename, text: text }
        texts << "[SOURCE: #{filename}]\n#{text}\n[END SOURCE]"
      end
      if @order.original_email_body.present?
        @file_chunks << { filename: "(이메일 본문)", text: @order.original_email_body }
        texts << "[SOURCE: (이메일 본문)]\n#{@order.original_email_body}\n[END SOURCE]"
      end
      texts.compact.join("\n\n")
    end

    # source_excerpt(원문 인용)에서 어느 파일에서 왔는지 추정.
    # 일치 안 되면 첫 chunk(가장 큰 가능성)로 fallback.
    def find_source_file(excerpt)
      return nil if excerpt.blank? || @file_chunks.blank?
      needle = excerpt.to_s.strip[0, 60]  # 처음 60자만 비교 — 충분히 unique
      @file_chunks.each do |chunk|
        return chunk[:filename] if chunk[:text].to_s.include?(needle)
      end
      # fallback — 가장 긴 chunk(주 첨부일 가능성 높음)
      @file_chunks.max_by { |c| c[:text].to_s.length }&.dig(:filename)
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
      step2 = @steps_result["step2_items"] || {}
      items = step2[:items] || []

      if items.any?
        # 품목 1개 → 11항목 체크리스트 task
        tasks = items.flat_map do |item|
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
      else
        # 품목 0개 → 문서 단위 11항목 점검을 task로 노출 (대표님이 결손 항목 한눈에 보도록)
        doc_missing = step2[:doc_level_missing] || REQUIRED_FIELDS
        tasks = REQUIRED_FIELDS.map do |field|
          {
            item_idx: 0,
            item_name: "(품목 추출 실패 — 문서 단위 점검)",
            field: field,
            label: REQUIRED_FIELD_LABELS[field],
            status: doc_missing.include?(field) ? "missing" : "ok"
          }
        end
      end

      { tasks: tasks, count: tasks.size, missing_count: tasks.count { |t| t[:status] == "missing" } }
    end

    # ── Step 4 — 공급사 탐색 (자체 DB + datago + google_cse) ──
    # ISS-358 (2026-05-10): Anthropic Web Search Tool 제거 — finder 결과만 반환.
    def step4_find_suppliers
      items = @steps_result.dig("step2_items", :items) || []
      return { status: "skipped", reason: "no items", suppliers: [] } if items.empty?

      candidates = RfqAuto::SupplierFinder.new(items, max_per_source: 5).call

      {
        suppliers: candidates,
        count:     candidates.size,
        sources:   candidates.map { |c| c[:source] }.tally
      }
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
