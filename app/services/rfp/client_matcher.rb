# ISS-335: Order에 client_id 자동 매핑
# 매칭 우선순위:
#   1. sender_domain == Client.website 도메인 정확 매칭
#   2. Ariba 파서 추출 owner/buyer + Client.name fuzzy (Jaro-Winkler)
#   3. 자사 도메인 (atoz2010.com 등)은 skip (내부 발신)
#   4. 미매칭 시 nil + admin 큐 (별도 이슈로 알림)
#
# 입력: Order
# 출력: { client: Client|nil, confidence: Float, source: String, reason: String }
module Rfp
  class ClientMatcher
    INTERNAL_DOMAINS = %w[atoz2010.com ddtl.co.kr atoz2004.com].freeze
    ARIBA_RELAY_DOMAINS = %w[ariba.com ansmtp.ariba.com smtp.mn1.ariba.com].freeze

    DOMAIN_ALIASES = {
      "enec.ae"        => "enec",
      "enecprogram.ae" => "enec",
      "nawah.ae"       => "enec",
      "barakah.ae"     => "enec",
      "kepco-enc.com"  => "kepco-enc",
      "kepco.co.kr"    => "kepco-enc",
      "khnp.co.kr"     => "khnp",
      "hdec.kr"        => "hyundai"
    }.freeze

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      domain = normalize_domain(@order.sender_domain.to_s)
      return skip("internal sender") if INTERNAL_DOMAINS.include?(domain)
      return skip("ariba relay only — no buyer info") if ARIBA_RELAY_DOMAINS.include?(domain) && @order.original_email_from.to_s.match?(/ariba\.com>?\z/i)

      # 1) Domain alias 우선 (예: enec.ae, nawah.ae → ENEC)
      if (key = DOMAIN_ALIASES[domain])
        client = find_client_by_alias(key)
        return matched(client, 0.95, "domain_alias:#{key}") if client
      end

      # 2) website 정확 매칭
      client = match_by_website(domain)
      return matched(client, 0.90, "website_match") if client

      # 3) Ariba relay인 경우 — original_from 도메인을 별도 추출 시도
      if ARIBA_RELAY_DOMAINS.include?(domain)
        real_domain = extract_real_sender_domain(@order.original_email_from.to_s)
        if real_domain && (key = DOMAIN_ALIASES[real_domain])
          client = find_client_by_alias(key)
          return matched(client, 0.85, "ariba_real_domain_alias:#{real_domain}") if client
        end
      end

      no_match("no domain/alias hit for #{domain}")
    rescue => e
      Rails.logger.warn("[Rfp::ClientMatcher] order=#{@order.id} #{e.class}: #{e.message}")
      no_match("error: #{e.message}")
    end

    private

    def normalize_domain(d)
      d.downcase.strip.sub(/\A.*@/, "").sub(/\A.*</, "").sub(/[>"'].*\z/, "")
    end

    def extract_real_sender_domain(from_str)
      m = from_str.match(/<([^@>]+@([^>]+))>/)
      return nil unless m
      m[2].downcase.strip
    end

    def find_client_by_alias(key)
      Client.where("LOWER(website) LIKE ? OR LOWER(name) LIKE ?", "%#{key}%", "%#{key}%").first
    end

    def match_by_website(domain)
      return nil if domain.blank?
      Client.where.not(website: [ nil, "" ]).find do |c|
        client_domain = normalize_domain(c.website)
        client_domain == domain || client_domain.end_with?(".#{domain}") || domain.end_with?(".#{client_domain}")
      end
    end

    def matched(client, confidence, source)
      { client: client, confidence: confidence, source: source, reason: "matched: #{client.name}" }
    end

    def no_match(reason)
      { client: nil, confidence: 0.0, source: "no_match", reason: reason }
    end

    def skip(reason)
      { client: nil, confidence: 0.0, source: "skipped", reason: reason }
    end
  end
end
