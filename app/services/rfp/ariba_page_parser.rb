# ISS-334: Ariba HTML/PDF 첨부에서 due_date / owner / event_type 등 메타데이터 추출
# 입력: ActiveStorage::Attachment (Ariba "Print version of the event" HTML)
# 출력: { due_date:, publish_date:, owner:, event_type:, currency:, commodity:, ariba_event_id:, source: }
#
# Ariba 표준 헤더 구조 (라벨-값 셀 쌍):
#   |Owner| |Bhargav Thakore|
#   |Event Type| |RFP|
#   |Currency| |UAE Dirham|
#   |Publish time| |3/25/2026 10:19 AM|
#   |Due date| |4/3/2026 10:15 AM|
module Rfp
  class AribaPageParser
    LABEL_VALUE_PAIRS = {
      due_date:     [ /Due\s*date/i, /Closing\s*(?:Date|Time)/i, /Bid\s*Closes?/i ],
      publish_date: [ /Publish\s*time/i, /Open\s*Date/i, /Issue\s*Date/i ],
      owner:        [ /\AOwner\z/i, /Buyer\s*Contact/i, /Project\s*Owner/i ],
      event_type:   [ /Event\s*Type/i ],
      currency:     [ /\ACurrency\z/i ],
      commodity:    [ /Commodity/i ]
    }.freeze

    DATE_FORMATS = [
      "%m/%d/%Y %I:%M %p",  # 4/3/2026 10:15 AM
      "%m/%d/%Y",            # 4/3/2026
      "%d/%m/%Y",            # 3/4/2026 (UAE 형식)
      "%Y-%m-%d %H:%M",      # 2026-04-03 10:15
      "%Y-%m-%d"
    ].freeze

    def self.call(attachment)
      new(attachment).call
    end

    def initialize(attachment)
      @attachment = attachment
    end

    def call
      raw = read_raw
      return empty_result("no content") if raw.blank?

      doc = Nokogiri::HTML(raw)
      doc.search("script, style").remove
      cells = extract_cells(doc)
      return empty_result("no table cells") if cells.empty?

      pairs = build_label_value_pairs(cells)
      result = LABEL_VALUE_PAIRS.transform_values { |patterns| find_value(pairs, patterns) }
      result[:due_date] = parse_date(result[:due_date])
      result[:publish_date] = parse_date(result[:publish_date])
      result[:ariba_event_id] = extract_event_id(raw)
      result[:source] = "ariba_parser"
      result
    rescue => e
      Rails.logger.warn("[Rfp::AribaPageParser] #{@attachment.blob.filename}: #{e.class}: #{e.message}")
      empty_result("error: #{e.message}")
    end

    private

    def read_raw
      content_type = @attachment.blob.content_type.to_s
      filename = @attachment.blob.filename.to_s
      ext = File.extname(filename).downcase
      return nil unless content_type.include?("html") || %w[.html .htm .doc].include?(ext)

      @attachment.open do |file|
        file.read
      end
    end

    def extract_cells(doc)
      doc.css("td, th").map { |el| el.text.gsub(/\s+/, " ").strip }.reject(&:empty?)
    end

    def build_label_value_pairs(cells)
      pairs = []
      cells.each_cons(2) do |label, value|
        next if label.length > 50
        next if value.length > 200
        pairs << [ label, value ]
      end
      pairs
    end

    def find_value(pairs, patterns)
      pairs.each do |label, value|
        patterns.each do |pat|
          return value if label =~ pat
        end
      end
      nil
    end

    def parse_date(str)
      return nil if str.blank?
      cleaned = str.gsub(/&nbsp;/, " ").strip
      DATE_FORMATS.each do |fmt|
        begin
          return Date.strptime(cleaned, fmt)
        rescue ArgumentError
          next
        end
      end
      nil
    end

    def extract_event_id(raw)
      m = raw.match(/(?:Doc|Event)[\s_]*(?:ID|Number|#)?[:\s]*(Doc\d{6,}|6\d{9})/i)
      m && m[1]
    end

    def empty_result(reason)
      {
        due_date: nil, publish_date: nil, owner: nil, event_type: nil,
        currency: nil, commodity: nil, ariba_event_id: nil,
        source: "ariba_parser", error: reason
      }
    end
  end
end
