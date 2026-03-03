module Gmail
  # 이메일 제목/본문에서 발주번호(PO Number)를 추출하는 서비스
  # 패턴 예시: 6000009324, PO-123456, RFQ-2024-001
  class ReferenceNumberExtractor
    PATTERNS = [
      /\b[6-9]\d{9}\b/,              # 6000009324 형식 (10자리, 6~9 시작)
      /\bRFQ[_\-\s](\d{6,10})\b/i,  # RFQ_6000009486, RFQ-2024-001 형식 (_포함)
      /\b[1-9]\d{8,9}\b/,           # 9~10자리 발주번호 일반형
      /\bPO[-\s]?\d{6,10}\b/i       # PO-123456 형식
    ].freeze

    # @param subject [String] 이메일 제목
    # @param body [String] 이메일 본문 (첫 500자만 탐색)
    # @return [String, nil] 추출된 발주번호 또는 nil
    def self.extract(subject, body = "")
      text = "#{subject} #{body.to_s.first(500)}"
      PATTERNS.each do |pattern|
        match = text.match(pattern)
        next unless match
        # 캡처 그룹이 있으면 첫 번째 그룹(숫자만), 없으면 전체 매치에서 구분자 제거
        return (match[1] || match[0]).gsub(/[-\s_]/, "")
      end
      nil
    end
  end
end
