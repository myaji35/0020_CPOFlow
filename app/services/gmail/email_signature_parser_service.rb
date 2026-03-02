# frozen_string_literal: true

module Gmail
  # Parses the email signature block from a plain-text or HTML email body.
  # Returns a hash with extracted fields: name, title, company, phone, mobile,
  # email, website, address, raw.
  #
  # Usage:
  #   result = Gmail::EmailSignatureParserService.parse(plain_body, html_body)
  #   # => { name: "John Kim", title: "Sales Manager", email: "john@example.com", ... }
  class EmailSignatureParserService
    # 서명 구분자 패턴 (이 라인 이후가 서명 블록)
    SIGNATURE_DELIMITERS = [
      /^--\s*$/,
      /^_{3,}$/,
      /^-{3,}$/,
      /^(Best\s+regards?|Kind\s+regards?|Regards?|Sincerely|Cheers|Thanks?|Warm\s+regards?|With\s+regards?)[,\s]*$/i,
      /^(감사합니다|안녕히\s*계세요|드림)[,\s.]*$/
    ].freeze

    PHONE_PATTERN  = /(?:T|Tel|Phone|Ph|Office|Direct|O)[\s.:]*(\+?[\d\s\-\(\)\.]{7,20})/i
    MOBILE_PATTERN = /(?:Mob(?:ile)?|Cell|M|HP|핸드폰|휴대폰)[\s.:]*(\+?[\d\s\-\(\)\.]{7,20})/i
    EMAIL_PATTERN  = /\b([a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})\b/
    URL_PATTERN    = /(?:https?:\/\/)?(?:www\.)[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}(?:\/[^\s]*)*/i
    COMPANY_PATTERN = /(?:Company|Co\.|Corp\.?|Inc\.?|Ltd\.?|LLC|회사|법인|주식회사|\(주\))[^\n]*/i

    # @param plain_body [String] 이메일 plain text body
    # @param html_body [String, nil] 이메일 HTML body (보조 소스)
    # @return [Hash] 파싱 결과 { name:, title:, company:, phone:, mobile:, email:, website:, address:, raw: }
    def self.parse(plain_body, html_body = nil)
      new(plain_body, html_body).parse
    end

    # 본문과 서명 블록을 분리하여 반환
    # @return [Hash] { body: String, signature: String|nil }
    def self.split(plain_body, html_body = nil)
      new(plain_body, html_body).split
    end

    def initialize(plain_body, html_body = nil)
      @plain_body = plain_body.to_s
      @html_body  = html_body.to_s
    end

    def split
      lines = @plain_body.lines
      delimiter_idx = find_delimiter_index(lines)

      if delimiter_idx
        {
          body: lines[0...delimiter_idx].join.rstrip,
          signature: lines[delimiter_idx..].join.strip
        }
      else
        { body: @plain_body, signature: nil }
      end
    end

    def parse
      sig_block = extract_signature_block(@plain_body)

      # plain body에서 서명을 못 찾으면 HTML → plain 변환 후 재시도
      if sig_block.blank? && @html_body.present?
        plain_from_html = html_to_plain(@html_body)
        sig_block = extract_signature_block(plain_from_html)
      end

      return {} if sig_block.blank?

      {
        name:    extract_name(sig_block),
        title:   extract_title(sig_block),
        company: extract_company(sig_block),
        phone:   extract_phone(sig_block),
        mobile:  extract_mobile(sig_block),
        email:   extract_email(sig_block),
        website: extract_website(sig_block),
        address: extract_address(sig_block),
        raw:     sig_block.strip
      }.compact
    end

    private

    # ──────────────────────────────
    # 서명 블록 추출
    # ──────────────────────────────

    # 구분자 라인의 인덱스를 반환 (없으면 nil)
    def find_delimiter_index(lines)
      lines.each_with_index do |line, idx|
        stripped = line.strip
        return idx if SIGNATURE_DELIMITERS.any? { |pat| stripped.match?(pat) }
      end
      nil
    end

    def extract_signature_block(text)
      lines = text.lines
      delimiter_idx = find_delimiter_index(lines)

      if delimiter_idx
        lines[(delimiter_idx + 1)..].join.strip
      else
        # 구분자 없으면 마지막 5줄을 서명으로 간주
        tail = lines.last(5).join.strip
        tail.length > 20 ? tail : nil
      end
    end

    # HTML → 줄 바꿈 유지 plain text 변환 (간단 버전)
    def html_to_plain(html)
      text = html.dup
      text.gsub!(/<br\s*\/?>/i, "\n")
      text.gsub!(/<\/p>/i, "\n")
      text.gsub!(/<\/div>/i, "\n")
      text.gsub!(/<[^>]+>/, "")
      CGI.unescapeHTML(text)
    end

    # ──────────────────────────────
    # 필드별 추출 메서드
    # ──────────────────────────────

    # 첫 번째 비어있지 않은 줄 (이름으로 추정)
    def extract_name(sig)
      lines = sig.lines.map(&:strip).reject(&:blank?)
      candidate = lines.first
      return nil if candidate.blank?

      # 이메일/전화번호/URL이 포함된 경우 이름이 아님
      return nil if candidate.match?(EMAIL_PATTERN)
      return nil if candidate.match?(/\+?[\d\s\-\(\)\.]{7,}/)
      return nil if candidate.match?(/https?:\/\/|www\./i)
      return nil if candidate.length > 60

      candidate
    end

    def extract_title(sig)
      lines = sig.lines.map(&:strip).reject(&:blank?)
      # 두 번째 줄에서 직책 키워드 포함 여부 확인
      title_keywords = /manager|director|engineer|officer|executive|president|
                        ceo|cto|coo|cfo|vp|head|lead|specialist|coordinator|
                        담당|부장|차장|과장|대리|사원|팀장|이사|상무|전무|대표/ix

      candidate = lines[1..4].to_a.find { |l|
        l.match?(title_keywords) && !l.match?(EMAIL_PATTERN) && l.length < 80
      }
      return nil unless candidate

      # "Sales Manager | ABC Trading Co." → "Sales Manager" 만 추출
      candidate.split(/\s*[|\/]\s*/).first&.strip
    end

    def extract_company(sig)
      # "직책 | 회사명" 패턴 우선 탐색
      lines = sig.lines.map(&:strip).reject(&:blank?)
      title_line = lines[1..4].to_a.find { |l| l.include?("|") || l.include?("/") }
      if title_line
        parts = title_line.split(/\s*[|\/]\s*/)
        company_candidate = parts[1..]&.join(" ")&.strip
        return company_candidate if company_candidate.present? && company_candidate.length < 60
      end

      # 회사 키워드 패턴 폴백
      match = sig.match(COMPANY_PATTERN)
      match ? match[0].strip : nil
    end

    def extract_phone(sig)
      # Mobile 패턴을 먼저 제거하고 나머지에서 전화 추출
      sig_without_mobile = sig.gsub(MOBILE_PATTERN, "")
      match = sig_without_mobile.match(PHONE_PATTERN)
      clean_number(match ? match[1] : nil)
    end

    def extract_mobile(sig)
      match = sig.match(MOBILE_PATTERN)
      clean_number(match ? match[1] : nil)
    end

    def extract_email(sig)
      match = sig.match(EMAIL_PATTERN)
      match ? match[1].downcase : nil
    end

    def extract_website(sig)
      match = sig.match(URL_PATTERN)
      match ? match[0] : nil
    end

    # 주소: 숫자 + 도로명 패턴 또는 'Street|Ave|Road|Rd|Abu Dhabi|Seoul|서울|서구|강남' 포함 줄
    def extract_address(sig)
      address_pattern = /\d+\s+[A-Za-z]|\bStreet\b|\bSt\b|\bAve\b|\bRoad\b|\bRd\b|
                         Abu\s+Dhabi|Dubai|Seoul|서울|부산|대구|경기|인천/xi
      line = sig.lines.map(&:strip).find { |l| l.match?(address_pattern) }
      line&.strip
    end

    def clean_number(str)
      return nil if str.blank?
      cleaned = str.strip.gsub(/\s{2,}/, " ")
      cleaned.length >= 7 ? cleaned : nil
    end
  end
end
