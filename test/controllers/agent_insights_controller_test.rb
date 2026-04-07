# frozen_string_literal: true

require "test_helper"

class AgentInsightsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "agent_insight_ctrl_test@example.com") do |u|
      u.name     = "Agent Insight Test User"
      u.password = "password123"
      u.role     = :member
    end
    login_as(@user)

    @order = Order.create!(
      title: "Insight Test Order",
      customer_name: "Cust",
      user: @user,
      status: :new_rfq
    )

    @insight = AgentInsight.create!(
      order: @order,
      insight_type: "due_date_risk",
      severity: :warning,
      title: "테스트 인사이트",
      body: "테스트 내용",
      dismissed: false
    )
  end

  def teardown
    @insight.destroy if AgentInsight.exists?(@insight.id)
    @order.destroy if Order.exists?(@order.id)
  end

  # ─── dismiss ─────────────────────────────

  test "dismiss — Turbo Stream 응답" do
    patch dismiss_agent_insight_path(@insight),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    @insight.reload
    assert @insight.dismissed
  end

  test "dismiss — HTML 폴백 리다이렉트" do
    patch dismiss_agent_insight_path(@insight)
    assert_redirected_to root_path
    @insight.reload
    assert @insight.dismissed
  end

  test "dismiss 후 dismissed=true 저장" do
    assert_equal false, @insight.dismissed
    patch dismiss_agent_insight_path(@insight)
    @insight.reload
    assert_equal true, @insight.dismissed
  end

  # ─── feedback ────────────────────────────

  test "feedback useful=true — 피드백 저장" do
    patch feedback_agent_insight_path(@insight, useful: "true")
    @insight.reload
    assert_equal true, @insight.useful
  end

  test "feedback useful=false — 피드백 저장" do
    patch feedback_agent_insight_path(@insight, useful: "false")
    @insight.reload
    assert_equal false, @insight.useful
  end

  test "feedback — Turbo Stream 응답" do
    patch feedback_agent_insight_path(@insight, useful: "true"),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
