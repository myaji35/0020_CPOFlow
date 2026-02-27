# frozen_string_literal: true

module Gmail
  # Analyzes a parsed email hash and determines if it is an RFQ.
  # Returns a score + matched keywords + extracted metadata.
  #
  # Usage:
  #   result = Gmail::RfqDetectorService.new(parsed_email).detect
  #   result[:is_rfq]   # => true/false
  #   result[:score]    # => 0..100
  #   result[:due_date] # => Date or nil
  class RfqDetectorService
    # SAP Ariba 초대 이메일 발신 도메인
    ARIBA_SENDER_DOMAINS = %w[
      ariba.com
      ansmtp.ariba.com
    ].freeze

    # SAP Ariba 이메일 감지 키워드 (제목/본문)
    ARIBA_KEYWORDS = [
      "has invited you to participate",
      "invited you to participate in an event",
      "ariba sourcing",
      "sap ariba",
      "ariba proposals",
      "respond to this event",
      "sourcing event"
    ].freeze

    # 자동 제외 발신 도메인 — 시스템 알림/송장 발송 서버 (Ariba 제외)
    EXCLUDED_SENDER_DOMAINS = %w[
      sap.com
      noreply.github.com
      notifications.google.com
      mailer.notion.so
      amazonses.com
      sendgrid.net
      mailchimp.com
      bounce.linkedin.com
      reply.github.com
    ].freeze

    # 제목에서 자동 제외할 패턴 — 알림성 이메일 식별
    EXCLUDED_SUBJECT_PATTERNS = [
      /invoice\s*(notification|alert|sent|ready)/i,
      /payment\s*(received|confirmation|notification)/i,
      /order\s*(confirmation|shipped|dispatched|delivered)/i,
      /\bnotification\s+from\b/i,
      /your\s+(order|invoice|shipment)\s+is/i,
      /\breceipt\b/i,
      /\bstatement\b/i,
      /unsubscribe/i,
      /do\s+not\s+reply/i,
      /no-?reply/i,
      /auto-?generated/i
    ].freeze

    # Weighted keyword groups (subject gets 2x weight)
    SUBJECT_KEYWORDS = [
      # English — RFQ / Quotation
      "rfq", "request for quotation", "quotation request",
      "request for quote", "inquiry", "enquiry",
      "price inquiry", "price request", "quote request",
      "tender", "bid request", "procurement inquiry",
      "rfp", "request for proposal", "invitation to bid",
      "itb", "material request", "mr ", "purchase request",
      "pr ", "supply request", "quotation needed",
      "please quote", "please provide quotation",
      "revised quotation", "revised quote", "re: quotation",
      "re: rfq", "re: quote", "follow up quotation",
      # Korean
      "견적요청", "견적 요청", "견적의뢰", "견적 의뢰",
      "구매요청", "발주요청", "입찰요청",
      "자재요청", "구매의뢰", "가격문의",
      "물량산출", "물량확인", "공급요청",
      "납품의뢰", "견적서 요청", "견적서 의뢰",
      # Arabic
      "طلب عرض أسعار", "طلب عرض سعر", "استفسار عن الأسعار",
      "طلب توريد", "طلب مشتريات",
      "طلب تسعير", "استفسار سعر", "طلب عطاء",
      "طلب مواد", "طلب شراء", "عرض سعر مطلوب",
      "مناقصة", "طلب توريد مواد"
    ].freeze

    BODY_KEYWORDS = [
      # English — request patterns
      "please provide", "please quote", "kindly provide",
      "kindly quote", "kindly send", "kindly advise",
      "please advise", "please confirm",
      "we require", "we need", "supply of",
      "delivery by", "due date", "required by",
      "urgently required", "asap", "urgent",
      "attached herewith", "please find attached",
      "as per attached", "as per below",
      "best price", "competitive price",
      "unit price", "total price",
      "bill of quantities", "boq", "bom",
      "bill of materials", "material list",
      "spec sheet", "specification",
      "lead time", "validity",
      # Korean
      "견적서", "납기", "납품일", "단가", "공급",
      "최저가", "단가표", "물량표", "자재목록",
      "긴급", "급합니다", "빨리", "조속히",
      # Construction / procurement materials
      "sika", "waterproofing", "concrete", "adhesive",
      "grout", "admixture", "sealant",
      "pipe", "valve", "fitting", "cable",
      "pump", "motor", "generator", "panel",
      "steel", "rebar", "cement", "paint",
      "insulation", "membrane", "epoxy"
    ].freeze

    # Date patterns to extract due date from email body
    DUE_DATE_PATTERNS = [
      /(?:delivery|due|required|납기|납품)\s*(?:by|date|일)?\s*:?\s*(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/i,
      /(?:delivery|due|required|납기|납품)\s*(?:by|date|일)?\s*:?\s*(\w+ \d{1,2},? \d{4})/i,
      /by\s+(\d{1,2}(?:st|nd|rd|th)?\s+\w+\s+\d{4})/i,
      /(\d{4}-\d{2}-\d{2})/  # ISO format anywhere in body
    ].freeze

    def initialize(parsed_email)
      @email   = parsed_email
      @subject = parsed_email[:subject].to_s.downcase
      @body    = parsed_email[:body].to_s.downcase
      @from    = parsed_email[:from].to_s.downcase
    end

    def detect
      # 0단계: SAP Ariba 초대 이메일 즉시 감지 (LLM 스킵)
      if ariba_sender?
        return ariba_rfq_result
      end

      # 1단계: 발신 도메인 / 제목 패턴으로 즉시 제외
      if excluded_sender? || excluded_subject?
        return not_rfq_result("발신자/제목 패턴으로 자동 제외 (알림성 이메일)", :excluded)
      end

      keyword_result = keyword_detect
      llm_result     = LlmRfqAnalyzerService.new(@email).analyze

      # 2단계: LLM이 명확히 RFQ 아님으로 판정 + 키워드도 없으면 제외
      if !llm_result[:is_rfq] && keyword_result[:score] < 20
        return not_rfq_result(llm_result[:reason] || "RFQ 아님", :excluded)
      end

      # Hybrid 점수: 키워드 40% + LLM 60%
      hybrid_score = (keyword_result[:score] * 0.4 + llm_result[:score] * 0.6).round

      # 3단계 판정: confirmed / uncertain / excluded
      rfq_verdict = if hybrid_score >= 70
        :confirmed
      elsif hybrid_score >= 30 || llm_result[:is_rfq]
        :uncertain
      else
        :excluded
      end

      {
        is_rfq:           rfq_verdict != :excluded,
        rfq_verdict:      rfq_verdict,          # :confirmed | :uncertain | :excluded
        score:            hybrid_score,
        confidence:       llm_result[:confidence],
        reason:           llm_result[:reason],
        subject_matches:  keyword_result[:subject_matches],
        body_matches:     keyword_result[:body_matches],
        due_date:         llm_result[:due_date] || keyword_result[:due_date],
        customer_name:    llm_result[:customer_name] || keyword_result[:customer_name],
        item_hints:       llm_result[:items]&.join(", ") || keyword_result[:item_hints],
        quantities:       llm_result[:quantities],
        project_name:     llm_result[:project_name],
        delivery_location: llm_result[:delivery_location],
        currency:         llm_result[:currency],
        estimated_value:  llm_result[:estimated_value],
        urgency:          llm_result[:urgency],
        llm_raw:          llm_result[:raw]
      }
    end

    def keyword_detect
      subject_score = score_subject
      body_score    = score_body
      total_score   = [ subject_score * 2 + body_score, 100 ].min

      {
        is_rfq:           total_score >= 30,
        score:            total_score,
        subject_matches:  matched_subject_keywords,
        body_matches:     matched_body_keywords,
        due_date:         extract_due_date,
        customer_name:    extract_customer_name,
        item_hints:       extract_item_hints,
        confidence:       confidence_label(total_score)
      }
    end

    private

    def ariba_sender?
      domain = sender_domain
      return false if domain.blank?
      ARIBA_SENDER_DOMAINS.any? { |d| domain == d || domain.end_with?(".#{d}") }
    end

    def ariba_rfq_result
      # 이메일 제목에서 Ariba 이벤트 ID 추출 (10자리 숫자)
      event_id_match = (@email[:subject].to_s + " " + @email[:body].to_s).match(/\b(\d{10})\b/)
      event_id = event_id_match&.[](1)

      # Ariba 이메일 본문에서 Owner(발주처) 파싱
      owner_match = @email[:body].to_s.match(/Owner:\s*([^\n\r]+)/i)
      customer = owner_match ? owner_match[1].strip : extract_customer_name

      {
        is_rfq:            true,
        is_ariba:          true,
        rfq_verdict:       :confirmed,
        score:             95,
        confidence:        "high",
        reason:            "SAP Ariba 소싱 이벤트 초대 이메일",
        subject_matches:   [ "ariba" ],
        body_matches:      [],
        due_date:          extract_due_date,
        customer_name:     customer,
        item_hints:        nil,
        quantities:        [],
        project_name:      nil,
        delivery_location: nil,
        currency:          nil,
        estimated_value:   nil,
        urgency:           "normal",
        ariba_event_id:    event_id,
        llm_raw:           {}
      }
    end

    def excluded_sender?
      domain = sender_domain
      return false if domain.blank?
      EXCLUDED_SENDER_DOMAINS.any? { |d| domain == d || domain.end_with?(".#{d}") }
    end

    def excluded_subject?
      EXCLUDED_SUBJECT_PATTERNS.any? { |pattern| @subject.match?(pattern) }
    end

    def not_rfq_result(reason, verdict = :excluded)
      {
        is_rfq:            false,
        rfq_verdict:       verdict,
        score:             0,
        confidence:        "none",
        reason:            reason,
        subject_matches:   [],
        body_matches:      [],
        due_date:          nil,
        customer_name:     extract_customer_name,
        item_hints:        nil,
        quantities:        [],
        project_name:      nil,
        delivery_location: nil,
        currency:          nil,
        estimated_value:   nil,
        urgency:           "normal",
        llm_raw:           {}
      }
    end

    def score_subject
      return 0 if @subject.blank?
      matched = SUBJECT_KEYWORDS.count { |kw| @subject.include?(kw.downcase) }
      [ matched * 25, 50 ].min
    end

    def score_body
      return 0 if @body.blank?
      matched = BODY_KEYWORDS.count { |kw| @body.include?(kw.downcase) }
      [ matched * 5, 50 ].min
    end

    def matched_subject_keywords
      SUBJECT_KEYWORDS.select { |kw| @subject.include?(kw.downcase) }
    end

    def matched_body_keywords
      BODY_KEYWORDS.select { |kw| @body.include?(kw.downcase) }
    end

    def extract_due_date
      DUE_DATE_PATTERNS.each do |pattern|
        match = (@email[:body].to_s + " " + @email[:subject].to_s).match(pattern)
        next unless match
        begin
          parsed = Date.parse(match[1])
          return parsed if parsed > Date.today
        rescue Date::Error, ArgumentError
          next
        end
      end
      nil
    end

    def sender_domain
      @sender_domain ||= @email[:from].to_s.match(/@([^>]+)>?/)&.[](1)&.strip&.downcase
    end

    def extract_customer_name
      # Try to extract company name from "From" header
      # e.g. "Ahmed Al-Rashid <ahmed@enec.gov.ae>" → "ENEC" from domain
      from = @email[:from].to_s
      name_match = from.match(/^"?([^"<]+)"?\s*</)
      return name_match[1].strip if name_match

      # Fallback: extract from email domain
      domain_match = from.match(/@([^.>]+)/)
      domain_match ? domain_match[1].upcase : "Unknown"
    end

    def extract_item_hints
      sika_products = [
        "MonoTop", "SikaTop", "Sikadur", "Sikaflex",
        "SikaGrout", "ViscoCrete", "Sikaplan", "Igolflex"
      ]
      hints = sika_products.select { |p| @body.include?(p.downcase) || @subject.include?(p.downcase) }
      hints.empty? ? nil : hints.join(", ")
    end

    def confidence_label(score)
      case score
      when 70..100 then "high"
      when 40..69  then "medium"
      when 20..39  then "low"
      else              "none"
      end
    end
  end
end
