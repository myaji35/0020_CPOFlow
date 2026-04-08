# frozen_string_literal: true

require "test_helper"

class OrderFlowsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "order_flows_test@example.com") do |u|
      u.name     = "OF Test"
      u.password = "password123"
      u.role     = :member
    end
    login_as(@user)
    @order = Order.create!(
      title: "Flow Test", customer_name: "FC",
      user: @user, status: :new_rfq, reference_no: "FC-001"
    )
  end

  test "GET /orders/:id/flow returns 200" do
    get order_flow_path(@order)
    assert_response :success
  end

  test "응답에 graph data 속성 포함" do
    get order_flow_path(@order)
    assert_match(/data-order-flow-graph-value/, response.body)
    assert_match(/Order:#{@order.id}/, response.body)
  end

  test "suggested 링크가 있으면 컨트롤러 변수에 포함" do
    other = Order.create!(title: "Other", customer_name: "FC", user: @user, status: :new_rfq, reference_no: "FC-002")
    OrderLink.create!(
      source: @order, target: other, relation: "references",
      status: "suggested", confidence: 0.7
    )
    get order_flow_path(@order)
    assert_response :success
    # suggested 링크가 그래프에 포함됨 (include_suggested: true)
    assert_match(/Order:#{other.id}/, response.body)
    # 제안 카드 partial 렌더링
    assert_match(/제안/, response.body)
    assert_match(/신뢰도 70%/, response.body)
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
