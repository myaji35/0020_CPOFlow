# frozen_string_literal: true

# LAB / RFQ Auto Phase 3 — 공급사 탐색 통합 서비스.
# 우선순위: 자체 Supplier DB → 한국 조달청 (data.go.kr) → Google Custom Search (UAE 등 해외)
# 각 소스는 키 미설정 시 graceful skip — 운영 환경 영향 X.
#
# 호출:
#   results = RfqAuto::SupplierFinder.new(items, max_per_source: 5).call
#   # => [{source:, confidence:, name:, email:, phone:, website:, country:, item_keyword:, ...}, ...]
require "net/http"
require "json"
require "uri"
require "cgi"

module RfqAuto
  class SupplierFinder
    SOURCES = %w[local_db web_search datago google_cse].freeze
    HTTP_TIMEOUT = 5  # seconds — 외부 API는 단계별 5초 cap

    attr_reader :web_cost_usd, :web_model, :web_citations, :web_error

    def initialize(items, max_per_source: 5, enable_web: true)
      @items = items.is_a?(Array) ? items : []
      @max   = max_per_source
      @enable_web = enable_web
      @web_cost_usd = 0.0
      @web_citations = []
      @web_error = nil
    end

    def call
      results = []

      # 1. 자체 DB — 키워드별 검색
      @items.first(3).each do |item|
        keyword = item[:name].to_s.presence || (item.is_a?(Hash) && item["name"].to_s.presence)
        next if keyword.blank?
        results.concat(search_local(keyword))
        results.concat(search_datago(keyword))
        results.concat(search_google(keyword))
      end

      # 2. Web Search (Anthropic) — 자체 DB가 비어있거나 미흡하면 발동
      if @enable_web && results.count { |r| r[:source] == "local_db" } == 0
        web_result = search_web
        results.concat(web_result[:suppliers] || [])
      end

      results.uniq { |r| [ r[:source], r[:name] ] }
    end

    private

    # ── Anthropic Web Search Tool — 신뢰도 60~90 (모델 추정) ────
    # D-3: 신뢰도 70+ 결과를 Supplier 테이블에 자동 저장 → 다음 분석부터 자체 DB hit.
    def search_web
      result = RfqAuto::WebSupplierFinder.new(@items, max_per_item: @max).call
      @web_cost_usd  = result[:cost_usd].to_f
      @web_model     = result[:model]
      @web_citations = result[:citations] || []

      # D-3: 신뢰도 70+ 자동 저장
      auto_save_high_confidence(result[:suppliers] || [])

      result
    rescue RfqAuto::WebSupplierFinder::AnthropicCreditError => e
      @web_error = "❗ Anthropic 잔액 부족 — 충전 후 재시도 (#{e.message.truncate(100)})"
      Rails.logger.warn "[SupplierFinder] #{@web_error}"
      { suppliers: [] }
    rescue StandardError => e
      @web_error = "#{e.class}: #{e.message.truncate(160)}"
      Rails.logger.warn "[SupplierFinder] web_search 실패: #{@web_error}"
      { suppliers: [] }
    end

    # 신뢰도 70+ + 이름/이메일/홈페이지 중 2개 이상 있으면 자동 저장.
    # 같은 이름 이미 있으면 skip (중복 차단).
    def auto_save_high_confidence(web_suppliers)
      return if web_suppliers.blank?
      saved = 0
      web_suppliers.each do |s|
        next if s[:confidence].to_i < 70
        next if s[:name].to_s.strip.blank?
        present_fields = [ s[:email], s[:website] ].count(&:present?)
        next if present_fields < 1  # 최소 이메일 또는 홈페이지

        # 이름 정규화 매칭 (대소문자/공백 무시)
        normalized = s[:name].to_s.strip.downcase
        existing = Supplier.where("LOWER(TRIM(name)) = ?", normalized).first
        next if existing  # 이미 있으면 skip

        Supplier.create!(
          name:           s[:name].to_s.strip[0, 200],
          contact_email:  s[:email].to_s[0, 100],
          contact_phone:  s[:phone].to_s[0, 50],
          website:        s[:website].to_s[0, 250],
          country:        s[:country].to_s[0, 10],
          auto_imported:  true,
          import_source:  "web_search",
          discovered_for: s[:item_keyword].to_s[0, 200],
          source_url:     s[:source_url].to_s[0, 500],
          notes:          "자동 import — Web Search (신뢰도 #{s[:confidence]}). #{s[:notes]}".strip[0, 500]
        )
        saved += 1
      end
      Rails.logger.info "[SupplierFinder] auto-imported #{saved} suppliers from web_search" if saved > 0
    rescue StandardError => e
      Rails.logger.warn "[SupplierFinder] auto_save 실패: #{e.class}: #{e.message}"
    end

    # ── 자체 Supplier DB — 신뢰도 90 ─────────────────────────────
    # D-7: 과거 거래이력 메타 함께 반환 (Order 건수, 총 추정가, 최근 거래일)
    # auto_imported 자동 등록은 60점 (검증 안 된 자동 import — 실 거래 시 90으로 승격).
    def search_local(keyword)
      Supplier.where("name LIKE ? OR ecount_code LIKE ?", "%#{keyword}%", "%#{keyword}%")
              .limit(@max)
              .map do |s|
        order_count = (s.orders.count rescue 0)
        order_value = (s.orders.sum(:estimated_value).to_f rescue 0.0)
        last_order  = (s.orders.maximum(:created_at) rescue nil)
        confidence = if s.try(:auto_imported) && order_count == 0
                       60  # 자동 import 미검증
                     elsif order_count >= 5
                       95  # 다회 거래 검증됨
                     else
                       85  # 일반 등록
                     end
        {
          source:        "local_db",
          confidence:    confidence,
          name:          s.name,
          email:         s.try(:contact_email) || s.try(:email),
          phone:         s.try(:contact_phone) || s.try(:phone),
          website:       s.try(:website),
          country:       s.try(:country),
          item_keyword:  keyword,
          source_url:    s.try(:source_url),
          # D-7 거래이력
          order_count:   order_count,
          order_value:   order_value,
          last_order_at: last_order,
          auto_imported: s.try(:auto_imported) || false,
          supplier_id:   s.id  # D-5/D-6 선택/이메일 발송용
        }
      end
    rescue StandardError => e
      Rails.logger.warn "[SupplierFinder] local search failed: #{e.message}"
      []
    end

    # ── 한국 조달청 (data.go.kr) — 신뢰도 70 ─────────────────────
    # 나라장터 물품식별번호 기반 등록업체 조회.
    # 키 없으면 skip. dev에선 ENV 또는 credentials.
    def search_datago(keyword)
      service_key = ENV["DATAGO_SERVICE_KEY"].presence ||
                    Rails.application.credentials.dig(:datago, :service_key)
      return [] if service_key.blank?

      # 조달청 물품정보 API: 품명 검색 → 등록업체
      url = URI("https://apis.data.go.kr/1230000/UsrEqpRegInfoService/getUsrEqpRegInfoList")
      url.query = URI.encode_www_form(
        serviceKey: service_key,
        type:       "json",
        numOfRows:  @max,
        pageNo:     1,
        prdctClsfcNoNm: keyword
      )

      response = Net::HTTP.start(url.host, url.port, use_ssl: true, read_timeout: HTTP_TIMEOUT) do |http|
        http.get(url.request_uri)
      end
      return [] unless response.code == "200"

      data = JSON.parse(response.body) rescue nil
      items = data&.dig("response", "body", "items") || []
      Array(items).first(@max).map do |it|
        {
          source:       "datago",
          confidence:   70,
          name:         it["bzentyNm"] || it["corpNm"] || "(이름 없음)",
          email:        it["emailAdrs"],
          phone:        it["telNo"],
          website:      it["hmpgAddr"],
          country:      "KR",
          item_keyword: keyword
        }
      end
    rescue StandardError => e
      Rails.logger.warn "[SupplierFinder] datago failed: #{e.class}: #{e.message}"
      []
    end

    # ── Google Custom Search — 신뢰도 40 ─────────────────────────
    # UAE 등 해외 업체 탐색용. CSE API 키 + Search Engine ID 필요.
    # 비용: $5/1000 쿼리 (Google).
    def search_google(keyword)
      api_key = ENV["GOOGLE_CSE_API_KEY"].presence ||
                Rails.application.credentials.dig(:google_cse, :api_key)
      cx = ENV["GOOGLE_CSE_CX"].presence ||
           Rails.application.credentials.dig(:google_cse, :cx)
      return [] if api_key.blank? || cx.blank?

      query = "#{keyword} supplier UAE OR distributor OR contact"
      url = URI("https://customsearch.googleapis.com/customsearch/v1")
      url.query = URI.encode_www_form(
        key:  api_key,
        cx:   cx,
        q:    query,
        num:  @max,
        gl:   "ae"  # UAE 우선
      )

      response = Net::HTTP.start(url.host, url.port, use_ssl: true, read_timeout: HTTP_TIMEOUT) do |http|
        http.get(url.request_uri)
      end
      return [] unless response.code == "200"

      data = JSON.parse(response.body) rescue nil
      items = data&.dig("items") || []
      items.first(@max).map do |it|
        link = it["link"].to_s
        host = (URI.parse(link).host rescue nil)
        {
          source:       "google_cse",
          confidence:   40,
          name:         it["title"].to_s.truncate(80),
          email:        nil,
          phone:        nil,
          website:      link,
          country:      host&.match?(/\.ae$/) ? "AE" : nil,
          item_keyword: keyword,
          snippet:      it["snippet"].to_s.truncate(160)
        }
      end
    rescue StandardError => e
      Rails.logger.warn "[SupplierFinder] google_cse failed: #{e.class}: #{e.message}"
      []
    end
  end
end
