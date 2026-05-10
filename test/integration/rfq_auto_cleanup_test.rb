require "test_helper"

# ISS-358 Wave 4 (T13) — 코드베이스 청소 + partial integration 검증.
#
# 검증 대상:
#   1. Anthropic Web Search 관련 잔존 참조 (코드베이스 grep)
#   2. shared/_atoz_rfq_items_table partial 의 :email / :screen 모드 동작
#   3. items 빈 배열 fallback 메시지
#   4. dual-key (string + symbol) 접근 통합
class RfqAutoCleanupTest < ActiveSupport::TestCase
  setup { I18n.locale = :ko }
  teardown { I18n.locale = I18n.default_locale }

  # ── 1. ENV cleanup grep ──────────────────────────────────────
  test "production code 에 Anthropic Web Search 잔존 참조 없음" do
    forbidden_patterns = %w[
      WebSupplierFinder
      web_supplier_finder
      RFQ_WEB_SEARCH_MODEL
    ]
    # search_web / enable_web 은 단어 경계 grep — 다른 메서드에 어휘적으로 안 겹치는지 별도 처리.

    paths = %w[app config lib].select { |p| Dir.exist?(p) }
    files = paths.flat_map do |p|
      Dir.glob("#{p}/**/*.{rb,erb,yml}").reject { |f| f.include?("/test/") }
    end

    violations = []
    forbidden_patterns.each do |pattern|
      files.each do |f|
        next unless File.exist?(f)
        content = File.read(f)
        if content.match?(/\b#{Regexp.escape(pattern)}\b/)
          violations << "#{f}: #{pattern}"
        end
      end
    end

    assert violations.empty?,
           "Wave 1 청소 잔재 발견:\n#{violations.join("\n")}"
  end

  test "search_web / enable_web / RfqAuto::WebSupplierFinder 식별자 부재" do
    # 위 grep 보다 좁은 — Ruby 식별자 단위 검사
    %w[search_web enable_web].each do |ident|
      paths = %w[app/services app/controllers app/views app/jobs lib].select { |p| Dir.exist?(p) }
      files = paths.flat_map { |p| Dir.glob("#{p}/**/*.{rb,erb}") }
      hits = files.select do |f|
        content = File.read(f)
        # def search_web / search_web( / .search_web 같은 식별자 호출 패턴
        content.match?(/(?:def\s+|\.|@)#{ident}\b/) || content.match?(/\b#{ident}:\s*[a-zA-Z]/)
      end
      assert hits.empty?, "#{ident} 잔존: #{hits.inspect}"
    end
  end

  # ── 2. _atoz_rfq_items_table partial — :email mode ────────────
  test "_atoz_rfq_items_table — :email 모드는 한국어 헤더 라벨 비표시" do
    items = [ { "name" => "TestEmail", "model" => "T-1", "manufacturer" => "Sika", "unit" => "EA", "quantity" => 5 } ]
    html = render_items_table(items: items, mode: :email)
    assert html.include?("TestEmail"), "item name 미렌더"
    assert html.include?("Manufacturer"), "컬럼 헤더 미렌더"
    # screen 전용 한국어 라벨은 :email 모드에서 안 나와야 함
    assert_not html.include?("품목 / Items Requested"), ":email 에 한국어 라벨 노출됨"
  end

  # ── 3. _atoz_rfq_items_table partial — :screen mode + i18n ────
  test "_atoz_rfq_items_table — :screen 모드 (ko) 는 한국어 라벨 노출" do
    items = [ { "name" => "TestScreenKo", "model" => "T-2", "unit" => "EA", "quantity" => 5 } ]
    I18n.with_locale(:ko) do
      html = render_items_table(items: items, mode: :screen)
      assert html.match?(/품목.*Items Requested/), "ko locale 한국어 라벨 미노출"
      assert html.include?("TestScreenKo")
    end
  end

  test "_atoz_rfq_items_table — :screen 모드 (en) 는 Items Requested 영문 라벨 노출" do
    items = [ { "name" => "TestScreenEn", "model" => "T-3", "unit" => "EA", "quantity" => 5 } ]
    I18n.with_locale(:en) do
      html = render_items_table(items: items, mode: :screen)
      assert html.include?("Items Requested"), "en locale Items Requested 미노출"
      assert html.include?("TestScreenEn")
    end
  end

  # ── 4. _atoz_rfq_items_table partial — empty fallback ─────────
  test "_atoz_rfq_items_table — 빈 items 시 fallback 메시지 표시" do
    html = render_items_table(items: [])
    assert html.include?("품목이 없습니다"), "빈 fallback 메시지 미노출"
    assert html.include?("No items extracted"), "영문 fallback 미노출"
  end

  # ── 5. dual-key (string + symbol) 통합 렌더 ───────────────────
  test "_atoz_rfq_items_table — dual-key (string + symbol) 모두 렌더" do
    items = [
      { "name" => "StringKey", "model" => "S-1", "manufacturer" => "Sika" },
      { name: "SymbolKey", model: "Y-1", manufacturer: "Hilti" }
    ]
    html = render_items_table(items: items)
    assert html.include?("StringKey"), "string-key item 미렌더"
    assert html.include?("SymbolKey"), "symbol-key item 미렌더"
    assert html.include?("Sika"), "string-key manufacturer 미렌더"
    assert html.include?("Hilti"), "symbol-key manufacturer 미렌더"
  end

  test "_atoz_rfq_items_table — Wave 0 4개 키 (manufacturer/brand/part_no/remarks) 모두 렌더" do
    items = [ {
      "name" => "FullItem",
      "manufacturer" => "Sika",
      "brand" => "Sika Pro",
      "part_no" => "SK-100",
      "remarks" => "QC pass",
      "unit" => "BAG",
      "quantity" => 50
    } ]
    html = render_items_table(items: items)
    # part_no 는 Model.Part No. 컬럼에 우선 표시 (model 비어있을 때 part_no 사용)
    assert html.include?("SK-100"), "part_no 미렌더"
    # manufacturer 는 Manufacturer.Brand 컬럼에 우선 표시
    assert html.include?("Sika"), "manufacturer 미렌더"
    # remarks 는 Remarks 컬럼에 표시
    assert html.include?("QC pass"), "remarks 미렌더"
  end

  private

  # partial 단독 렌더 — ApplicationController.renderer 사용 → controller 컨텍스트 (i18n) 작동
  def render_items_table(items:, mode: nil)
    locals = { items: items }
    locals[:mode] = mode if mode
    ApplicationController.renderer.render(
      partial: "shared/atoz_rfq_items_table",
      locals: locals
    )
  end
end
