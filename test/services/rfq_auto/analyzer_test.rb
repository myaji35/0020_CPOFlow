require "test_helper"

# ISS-358 Wave 4 (T10) — Analyzer enriched.map 4개 키 통과 검증.
# Wave 0c (commit 2aa567f) 에서 추가된 manufacturer/brand/part_no/remarks 가
# pick() helper 를 통해 dual-key (string/symbol) 로 정상 추출되는지 단위 검증.
#
# 분석기 전체 통합 (Anthropic API 실호출) 은 비용/플래키 이슈로 Wave 4 범위 외.
module RfqAuto
  class AnalyzerTest < ActiveSupport::TestCase
    setup { I18n.locale = :ko }

    test "REQUIRED_FIELDS 11항목 + 라벨 매핑 완비" do
      assert_equal 11, RfqAuto::Analyzer::REQUIRED_FIELDS.size
      RfqAuto::Analyzer::REQUIRED_FIELDS.each do |field|
        assert RfqAuto::Analyzer::REQUIRED_FIELD_LABELS.key?(field),
               "REQUIRED_FIELD_LABELS 누락: #{field}"
      end
    end

    test "pick() helper 가 string-key item 에서 4개 키를 추출" do
      analyzer = build_analyzer
      item = {
        "name" => "SikaSet Plus",
        "manufacturer" => "Sika",
        "brand" => "Sika Pro",
        "part_no" => "SK-100",
        "remarks" => "QC pass"
      }
      assert_equal "Sika",     analyzer.send(:pick, item, :manufacturer, :maker)
      assert_equal "Sika Pro", analyzer.send(:pick, item, :brand)
      assert_equal "SK-100",   analyzer.send(:pick, item, :part_no, :part_number, :sku)
      assert_equal "QC pass",  analyzer.send(:pick, item, :remarks, :notes, :note)
    end

    test "pick() helper 가 symbol-key item 에서도 4개 키를 추출" do
      analyzer = build_analyzer
      item = {
        name: "SikaProof",
        manufacturer: "Sika",
        brand: "Sika WP",
        part_no: "SP-200",
        remarks: "10kg bag"
      }
      assert_equal "Sika",    analyzer.send(:pick, item, :manufacturer, :maker)
      assert_equal "Sika WP", analyzer.send(:pick, item, :brand)
      assert_equal "SP-200",  analyzer.send(:pick, item, :part_no, :part_number, :sku)
      assert_equal "10kg bag", analyzer.send(:pick, item, :remarks, :notes, :note)
    end

    test "pick() helper 가 alias 키도 인식 (manufacturer→maker, part_no→part_number/sku, remarks→notes/note)" do
      analyzer = build_analyzer
      assert_equal "Hyosung", analyzer.send(:pick, { "maker" => "Hyosung" }, :manufacturer, :maker)
      assert_equal "PN-9",    analyzer.send(:pick, { "part_number" => "PN-9" }, :part_no, :part_number, :sku)
      assert_equal "SKU-1",   analyzer.send(:pick, { "sku" => "SKU-1" }, :part_no, :part_number, :sku)
      assert_equal "ship by Mon", analyzer.send(:pick, { "note" => "ship by Mon" }, :remarks, :notes, :note)
      assert_equal "carry-on", analyzer.send(:pick, { "notes" => "carry-on" }, :remarks, :notes, :note)
    end

    test "pick() helper 빈 문자열 / nil 은 다음 alias 로 fallback" do
      analyzer = build_analyzer
      # "" (presence false) 면 다음 키로 진행
      assert_equal "Sika", analyzer.send(:pick, { "manufacturer" => "", "maker" => "Sika" }, :manufacturer, :maker)
      assert_nil analyzer.send(:pick, {}, :manufacturer, :maker)
    end

    private

    # Analyzer 인스턴스 빌드 (실 DB 분석은 호출하지 않음 — pick helper 검증 전용).
    # OpenStruct 로 minimal stub.
    def build_analyzer
      stub_order    = OpenStruct.new(attachments: [], reference_no: nil, rfq_no: nil, original_email_body: nil)
      stub_analysis = OpenStruct.new(order: stub_order, id: 0)
      RfqAuto::Analyzer.new(stub_analysis)
    end
  end
end
