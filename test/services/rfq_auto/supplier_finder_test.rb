require "test_helper"

# ISS-358 Wave 4 (T11) — SupplierFinder 회귀 테스트.
# Wave 1 (commit 9ff3b81) 에서 Anthropic Web Search Tool 제거 후 검증:
#   * SOURCES 에 web_search 미포함
#   * search_web / auto_save_high_confidence 메서드 부재
#   * web_* accessor (cost/model/citations/error) 부재
#   * 호출 결과에 source: "web_search" 포함되지 않음
module RfqAuto
  class SupplierFinderTest < ActiveSupport::TestCase
    setup { I18n.locale = :ko }

    test "SOURCES 가 local_db / datago / google_cse 3종만 — web_search 미포함" do
      assert_equal %w[local_db datago google_cse], RfqAuto::SupplierFinder::SOURCES
      assert_not_includes RfqAuto::SupplierFinder::SOURCES, "web_search"
    end

    test "search_web 메서드 부재 (Wave 1 삭제됨)" do
      finder = RfqAuto::SupplierFinder.new([ { name: "test" } ])
      assert_not finder.respond_to?(:search_web)
      assert_not finder.respond_to?(:search_web, true), "private :search_web 도 없어야 함"
    end

    test "auto_save_high_confidence 메서드 부재 (Wave 1 삭제됨)" do
      finder = RfqAuto::SupplierFinder.new([ { name: "test" } ])
      assert_not finder.respond_to?(:auto_save_high_confidence)
      assert_not finder.respond_to?(:auto_save_high_confidence, true), "private :auto_save_high_confidence 도 없어야 함"
    end

    test "web_* accessor 부재 (web_cost_usd/web_model/web_citations/web_error)" do
      finder = RfqAuto::SupplierFinder.new([ { name: "test" } ])
      %i[web_cost_usd web_model web_citations web_error].each do |m|
        assert_not finder.respond_to?(m), "#{m} accessor 가 남아있음"
      end
    end

    test "initialize signature 에 enable_web kwarg 미존재 — max_per_source 만 인자" do
      # max_per_source 만 받는다 (enable_web 받으면 ArgumentError)
      assert_nothing_raised { RfqAuto::SupplierFinder.new([ { name: "test" } ]) }
      assert_nothing_raised { RfqAuto::SupplierFinder.new([ { name: "test" } ], max_per_source: 3) }
      assert_raises(ArgumentError) do
        RfqAuto::SupplierFinder.new([ { name: "test" } ], enable_web: true)
      end
    end

    test "call 결과는 Array — 어떤 source 도 web_search 가 아님" do
      # ENV 키 미설정 시 datago/google_cse 자동 skip → local_db 만 시도.
      # local 도 매칭 안 되면 빈 배열. 어쨌든 Array 반환 + web_search 비포함.
      finder = RfqAuto::SupplierFinder.new([ { name: "NonExistentItemName-#{SecureRandom.hex(4)}" } ])
      result = finder.call
      assert_kind_of Array, result
      sources = result.map { |r| r[:source] || r["source"] }.compact.uniq
      assert_not_includes sources, "web_search"
    end

    test "items 빈 배열이어도 정상 처리 (빈 Array 반환)" do
      finder = RfqAuto::SupplierFinder.new([])
      assert_equal [], finder.call
    end

    test "items 가 Array 가 아니면 빈 배열로 정규화" do
      finder = RfqAuto::SupplierFinder.new(nil)
      assert_equal [], finder.call
    end
  end
end
