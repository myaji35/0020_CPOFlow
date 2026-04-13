# frozen_string_literal: true

module Gmail
  module Stage1
    # ISS-045 Phase A: 3단 필터 Stage 1 — 규칙 기반 게이트 (LLM 호출 0원)
    #
    # 목적: 하루 400통 중 ~70%를 LLM 호출 전에 결정지어 비용 절감.
    # 동작:
    #   - whitelist 도메인 또는 강/약 RFQ 신호 매칭 → Stage 2 (Haiku) 진입
    #   - 신호 0개 + 비whitelist 도메인 → reject_no_signal (excluded 후보)
    #
    # Shadow Mode 안전장치: reject_no_signal 건도 classification_logs에 기록 →
    # 방식 2 백그라운드 경로가 사용자 bulk_to_kanban 액션과 대조하여 FN 검출.
    #
    # Usage:
    #   result = Gmail::Stage1::RuleGate.decide(parsed_email)
    #   result.action      # => :pass_to_llm | :reject_no_signal | :whitelist_fast
    #   result.reason      # => "whitelist_domain" | "strong_keyword" | ...
    #   result.signals     # => ["kepco.co.kr", "rfq"]
    class RuleGate
      # 초기 시드 whitelist. 동적 확장: RfqFeedback.confirmed 3건 이상 도메인.
      WHITELIST_DOMAINS = Set.new(%w[
        adnoc.ae kepco.co.kr samsungeng.com hyundai-eng.com
        qatarrail.qa neom.sa shapoorji.ae aldarproperties.ae
        enec.gov.ae pcfc.ae ariba.com ansmtp.ariba.com
        dubaimetro.ae lottecon.com binladin.sa adport.ae
      ]).freeze

      # 강 신호: 제목/본문에 1개라도 매칭되면 즉시 Stage 2
      STRONG_RFQ_KEYWORDS = [
        /\brfq\b/i,
        /request\s+for\s+quot/i,
        /\btender\b/i,
        /\brfp\b/i,
        /\bitb\b/i,
        /invitation\s+to\s+bid/i,
        /견적\s*요청/,
        /견적\s*의뢰/,
        /입찰\s*요청/,
        /견적서/,
        /طلب\s*عرض/,
        /طلب\s*تسعير/,
        /مناقصة/
      ].freeze

      # 약 신호: 본문 맥락으로 RFQ 가능성 (Sika 제품, 수량 단위, 통화 등)
      WEAK_SIGNALS = [
        /\b(sika|monotop|viscocrete|sikadur|sikaflex|sikagrout)/i,
        /\b(waterproofing|concrete|epoxy|sealant|grout|admixture)/i,
        /\d+\s*(kg|ton|cartridge|drum|pcs|set|meter|m2|m3)/i,
        /\b(USD|AED|KRW|SAR|QAR)\s*\d/,
        /납기|단가|물량|공급/
      ].freeze

      Result = Data.define(:action, :reason, :signals) do
        def pass? = action == :pass_to_llm || action == :whitelist_fast
        def reject? = action == :reject_no_signal
      end

      # @param parsed_email [Hash] { subject:, from:, body: }
      # @return [Result]
      def self.decide(parsed_email)
        new(parsed_email).decide
      end

      def initialize(email)
        @email  = email
        @domain = extract_domain(email[:from])
        @text   = "#{email[:subject]} #{email[:body].to_s.first(4000)}"
      end

      def decide
        return Result.new(:whitelist_fast, "whitelist_domain", [ @domain ]) if whitelist?

        strong = STRONG_RFQ_KEYWORDS.select { |r| @text.match?(r) }
        weak   = WEAK_SIGNALS.select { |r| @text.match?(r) }

        if strong.any?
          Result.new(:pass_to_llm, "strong_keyword", strong.map(&:source))
        elsif weak.any?
          Result.new(:pass_to_llm, "weak_signal", weak.map(&:source))
        else
          Result.new(:reject_no_signal, "no_rfq_signal", [])
        end
      end

      private

      def whitelist?
        return false if @domain.nil? || @domain.empty?

        WHITELIST_DOMAINS.include?(@domain) || dynamic_whitelist.include?(@domain)
      end

      def dynamic_whitelist
        Rails.cache.fetch("rule_gate/dynamic_whitelist", expires_in: 1.day) do
          if defined?(RfqFeedback)
            Set.new(
              RfqFeedback.where(verdict: "confirmed")
                         .group(:sender_domain)
                         .having("count(*) >= 3")
                         .pluck(:sender_domain)
                         .compact
            )
          else
            Set.new
          end
        rescue StandardError => e
          Rails.logger.warn "[Stage1::RuleGate] dynamic_whitelist failed: #{e.class} #{e.message}"
          Set.new
        end
      end

      def extract_domain(from)
        from.to_s.match(/@([^>\s]+)/)&.[](1)&.strip&.downcase
      end
    end
  end
end
