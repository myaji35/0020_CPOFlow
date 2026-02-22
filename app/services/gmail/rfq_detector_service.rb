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
    # Weighted keyword groups (subject gets 2x weight)
    SUBJECT_KEYWORDS = [
      # English
      "rfq", "request for quotation", "quotation request",
      "request for quote", "inquiry", "enquiry",
      "price inquiry", "price request", "quote request",
      "tender", "bid request", "procurement inquiry",
      # Korean
      "견적요청", "견적 요청", "견적의뢰", "견적 의뢰",
      "구매요청", "발주요청", "입찰요청",
      # Arabic
      "طلب عرض أسعار", "طلب عرض سعر", "استفسار عن الأسعار",
      "طلب توريد", "طلب مشتريات"
    ].freeze

    BODY_KEYWORDS = [
      "please provide", "please quote", "kindly provide",
      "we require", "we need", "supply of",
      "delivery by", "due date", "required by",
      "urgently required", "asap",
      "견적서", "납기", "납품일", "단가", "공급",
      "sika", "waterproofing", "concrete", "adhesive",
      "grout", "admixture", "sealant"
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
      keyword_result = keyword_detect
      llm_result     = LlmRfqAnalyzerService.new(@email).analyze

      # Hybrid 점수: 키워드 40% + LLM 60%
      hybrid_score = (keyword_result[:score] * 0.4 + llm_result[:score] * 0.6).round

      {
        is_rfq:           hybrid_score >= 30 || llm_result[:is_rfq],
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
