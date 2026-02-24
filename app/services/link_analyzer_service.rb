# frozen_string_literal: true

# LinkAnalyzerService: 이메일 본문 링크 URL에 접속하여 텍스트를 추출하고
# Gemini API로 RFQ 관련 핵심 내용을 요약한다.
#
# Usage:
#   result = LinkAnalyzerService.analyze("https://example.com/rfq-spec.html")
#   # => { success: true, title: "...", summary: "...", raw_text: "..." }
class LinkAnalyzerService
  GEMINI_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent"
  MAX_TEXT_LENGTH = 8_000   # Gemini에 보낼 최대 텍스트 길이
  FETCH_TIMEOUT   = 10      # HTTP 접속 타임아웃 (초)
  MAX_RESPONSE_SIZE = 2.megabytes

  # 지원하지 않는 도메인 (로그인 필요 / 크롤링 차단)
  SKIP_DOMAINS = %w[
    accounts.google.com login.microsoftonline.com linkedin.com
    facebook.com twitter.com instagram.com youtube.com
    mail.google.com outlook.live.com
  ].freeze

  # SSRF 방지: 내부 네트워크 IP 범위
  PRIVATE_IP_RANGES = [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),  # Link-local (AWS metadata)
    IPAddr.new("::1/128"),          # IPv6 loopback
    IPAddr.new("fc00::/7")          # IPv6 private
  ].freeze

  def self.analyze(url)
    new(url).analyze
  end

  def initialize(url)
    @url = url.to_s.strip
  end

  def analyze
    return error_result("URL이 비어 있습니다") if @url.blank?
    return error_result("지원하지 않는 URL 형식입니다") unless valid_url?
    return error_result("로그인이 필요한 서비스입니다 (자동 접속 불가)") if skip_domain?
    return error_result("내부 네트워크 주소는 접근할 수 없습니다") if private_ip?

    raw_text, title = fetch_page_text
    return error_result("페이지 내용을 가져올 수 없습니다") if raw_text.blank?

    summary = summarize_with_gemini(raw_text, title)

    {
      success: true,
      url:     @url,
      title:   title,
      summary: summary,
      raw_text: raw_text.truncate(500)
    }
  rescue => e
    Rails.logger.error "[LinkAnalyzer] Error for #{@url}: #{e.message}"
    error_result("분석 중 오류가 발생했습니다: #{e.message.truncate(100)}")
  end

  private

  def valid_url?
    uri = URI.parse(@url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def skip_domain?
    host = URI.parse(@url).host.to_s.downcase
    SKIP_DOMAINS.any? { |d| host.include?(d) }
  rescue
    false
  end

  # SSRF 방지: 도메인을 DNS로 해석하여 내부 IP인지 확인
  def private_ip?
    require "resolv"
    host = URI.parse(@url).host.to_s
    # IP 주소 직접 입력 체크
    begin
      ip = IPAddr.new(host)
      return PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      # 도메인명 → DNS 해석
    end

    addresses = Resolv.getaddresses(host)
    addresses.any? do |addr|
      ip = IPAddr.new(addr)
      PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
    end
  rescue
    false
  end

  def fetch_page_text
    uri = URI.parse(@url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = FETCH_TIMEOUT
    http.read_timeout = FETCH_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "Mozilla/5.0 (compatible; CPOFlow/1.0; +https://cpoflow.app)"
    request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    request["Accept-Language"] = "ko,en;q=0.9"

    response = http.request(request)

    # 리다이렉트 처리 (최대 3회)
    redirects = 0
    while response.is_a?(Net::HTTPRedirection) && redirects < 3
      redirect_url = response["location"]
      return [ "", "" ] if redirect_url.blank?
      redirects += 1
      response = Net::HTTP.get_response(URI.parse(redirect_url))
    end

    return [ "", "" ] unless response.is_a?(Net::HTTPSuccess)
    return [ "", "" ] if response.body.to_s.bytesize > MAX_RESPONSE_SIZE

    body = response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)

    # Nokogiri로 HTML 파싱
    require "nokogiri"
    doc = Nokogiri::HTML(body)

    # 제목 추출
    title = doc.at("title")&.text&.strip ||
            doc.at("h1")&.text&.strip || ""

    # 불필요한 요소 제거
    doc.css("script, style, nav, footer, header, aside, .menu, .nav, .sidebar, .advertisement, .cookie").remove

    # 텍스트 추출 (body > main > article 우선)
    content_node = doc.at("main") || doc.at("article") || doc.at(".content") || doc.at("body")
    text = content_node&.text || doc.text

    # 공백 정리
    clean_text = text.gsub(/\s+/, " ").strip.truncate(MAX_TEXT_LENGTH)

    [ clean_text, title ]
  rescue Net::OpenTimeout, Net::ReadTimeout
    [ "", "" ]
  rescue => e
    Rails.logger.warn "[LinkAnalyzer] Fetch failed for #{@url}: #{e.message}"
    [ "", "" ]
  end

  def summarize_with_gemini(text, title)
    api_key = Rails.application.credentials.dig(:gemini, :api_key)
    return "Gemini API 키가 설정되지 않았습니다." if api_key.blank?

    prompt = <<~PROMPT
      다음은 이메일에 포함된 링크에서 가져온 웹 페이지 내용입니다.
      페이지 제목: #{title}

      이 내용에서 구매/조달 관련 핵심 정보를 한국어로 간결하게 요약해주세요:
      - 제품명, 규격, 수량
      - 납기일 또는 긴급도
      - 프로젝트명 또는 현장
      - 특이사항

      정보가 없는 항목은 제외하고, 없는 정보를 만들지 마세요.
      요약이 불가능하면 "구매/조달 관련 정보를 찾을 수 없습니다."라고만 응답하세요.

      페이지 내용:
      #{text}
    PROMPT

    uri = URI("#{GEMINI_ENDPOINT}?key=#{api_key}")
    body = {
      contents: [ { parts: [ { text: prompt } ] } ],
      generationConfig: { temperature: 0.2, maxOutputTokens: 500 }
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = body

    response = http.request(request)
    data = JSON.parse(response.body)

    data.dig("candidates", 0, "content", "parts", 0, "text") ||
      "AI 요약을 생성할 수 없습니다."
  rescue => e
    Rails.logger.error "[LinkAnalyzer] Gemini error: #{e.message}"
    "요약 생성 중 오류가 발생했습니다."
  end

  def error_result(message)
    { success: false, url: @url, error: message }
  end
end
