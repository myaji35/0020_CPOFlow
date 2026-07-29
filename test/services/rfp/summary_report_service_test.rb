require "test_helper"

class Rfp::SummaryReportServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "Summary User", email: "summary-#{SecureRandom.hex(4)}@test.local", password: "password123")
    @order = Order.create!(title: "Pump RFQ", customer_name: "Test Client", user: @user, status: :new_rfq)
  end

  test "items 배열로 한국어 마크다운 표를 생성한다" do
    markdown = service("items" => [{ "name" => "Pressure Gauge", "model" => "PG-100", "quantity" => 3, "unit" => "EA" }]).build_markdown_ko

    assert_includes markdown, "| # | 품목 | 모델 | 사양 | 수량 | 단위 | 납기 | 인증 |"
    assert_includes markdown, "Pressure Gauge"
  end

  test "items가 비어 있으면 품목 없음 안내를 표시한다" do
    markdown = service("items" => []).build_markdown_ko

    assert_includes markdown, "품목 없음"
  end

  test "nil 필드는 대시로 렌더한다" do
    markdown = service("items" => [{ "name" => "Valve", "model" => nil, "spec" => nil, "quantity" => nil }]).build_markdown_ko

    assert_includes markdown, "| 1 | Valve | - | - | - | - | - | - |"
  end

  test "LLM 실패 시 실패 사실을 명시하고 영문 요약을 지어내지 않는다" do
    failing_service = Class.new(Rfp::SummaryReportService) do
      def generate_summary_en
        nil
      end
    end
    report = failing_service.new(@order, "items" => [{ "name" => "Valve" }]).call

    assert report[:llm_failed]
    assert_equal Rfp::SummaryReportService::FAILURE_MESSAGE, report[:summary_en]
    assert_nil report[:cost_usd]
  end

  test "call 결과에 items 와 deadline 구조화 데이터가 포함된다" do
    failing_service = Class.new(Rfp::SummaryReportService) do
      def generate_summary_en
        nil
      end
    end
    report = failing_service.new(
      @order,
      "items" => [{ "name" => "Valve", "quantity" => 2, "unit" => "EA" }],
      "rfp_deadline" => "2026-08-01"
    ).call

    assert_equal [{ name: "Valve", quantity: 2, unit: "EA" }], report[:items]
    assert_equal "2026-08-01", report[:deadline]
  end

  private

  def service(result)
    Rfp::SummaryReportService.new(@order, result)
  end
end
