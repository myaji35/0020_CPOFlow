# frozen_string_literal: true

# LAB / RFQ Auto Phase 3 — 공급사 탐색 통합 서비스.
# 우선순위: 자체 Supplier DB → 한국 조달청 (data.go.kr) → Google Custom Search (UAE 등 해외)
# 각 소스는 키 미설정 시 graceful skip — 운영 환경 영향 X.
#
# ISS-358 (2026-05-10): Anthropic Web Search Tool 제거 — datago/google_cse/local_db만 유지.
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
    SOURCES = %w[local_db datago google_cse].freeze
    HTTP_TIMEOUT = 5  # seconds — 외부 API는 단계별 5초 cap

    def initialize(items, max_per_source: 5)
      @items = items.is_a?(Array) ? items : []
      @max   = max_per_source
    end

    def call
      results = []

      # 자체 DB → datago → google_cse 순으로 키워드별 검색
      @items.first(3).each do |item|
        keyword = item[:name].to_s.presence || (item.is_a?(Hash) && item["name"].to_s.presence)
        next if keyword.blank?
        results.concat(search_local(keyword))
        results.concat(search_datago(keyword))
        results.concat(search_google(keyword))
      end

      results.uniq { |r| [ r[:source], r[:name] ] }
    end

    private

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
