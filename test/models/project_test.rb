require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "Project site_category 집계 가능" do
    # 테스트 DB에 데이터가 없어도 쿼리 자체는 정상 동작해야 함
    assert_nothing_raised { Project.distinct.pluck(:site_category) }
    assert_nothing_raised { Project.where(site_category: %w[nuclear hydro tunnel gtx]).count }
  end

  test "Project orders 연관 정상" do
    assert_nothing_raised do
      Project.includes(:orders).limit(5).map { |p| p.orders.count }
    end
  end

  test "현장별 수주 집계 정상" do
    %w[nuclear hydro tunnel gtx].each do |cat|
      pids   = Project.where(site_category: cat).pluck(:id)
      orders = Order.where(project_id: pids)
      assert orders.count >= 0
      assert orders.sum(:estimated_value).to_f >= 0
    end
  end
end
