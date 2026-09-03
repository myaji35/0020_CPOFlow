# frozen_string_literal: true

require "test_helper"

class Admin::AgentRunsControllerTest < ActionDispatch::IntegrationTest
  def setup
    AgentRun.delete_all
    @admin = user_for("admin_agent_runs_test@example.com", :admin)
    @manager = user_for("manager_agent_runs_test@example.com", :manager)
    @member = user_for("member_agent_runs_test@example.com", :member)
  end

  test "admin can view index" do
    login_as(@admin)
    get admin_agent_runs_path
    assert_response :success
  end

  test "manager is redirected to root" do
    login_as(@manager)
    get admin_agent_runs_path
    assert_redirected_to root_path
  end

  test "member is redirected to root" do
    login_as(@member)
    get admin_agent_runs_path
    assert_redirected_to root_path
  end

  test "empty database shows empty state" do
    login_as(@admin)
    get admin_agent_runs_path
    assert_response :success
    assert_includes response.body, "기록된 에이전트 실행이 없습니다"
  end

  test "shows run count and total cost" do
    create_run(agent_name: "cost-agent", cost_usd: 0.1234)
    create_run(agent_name: "cost-agent", cost_usd: 0.2000)

    login_as(@admin)
    get admin_agent_runs_path
    assert_response :success
    assert_select "section", text: /실행 수.*2/m
    assert_includes response.body, "$0.3234"
  end

  test "window 24h filters old runs" do
    create_run(agent_name: "recent-agent", started_at: 1.hour.ago)
    create_run(agent_name: "old-agent", started_at: 2.days.ago)

    login_as(@admin)
    get admin_agent_runs_path, params: { window: "24h" }
    assert_response :success
    assert_select "tbody", text: /recent-agent/
    assert_select "tbody", { text: /old-agent/, count: 0 }
  end

  test "agent exact-match filter changes rows" do
    create_run(agent_name: "alpha-agent")
    create_run(agent_name: "beta-agent")

    login_as(@admin)
    get admin_agent_runs_path, params: { agent: "alpha-agent" }
    assert_response :success
    assert_select "tbody", text: /alpha-agent/
    assert_select "tbody", { text: /beta-agent/, count: 0 }
  end

  test "status filter changes rows" do
    create_run(agent_name: "successful-agent", status: "success")
    create_run(agent_name: "failed-agent", status: "failure", error_message: "filtered failure")

    login_as(@admin)
    get admin_agent_runs_path, params: { status: "failure" }
    assert_response :success
    assert_select "tbody", text: /failed-agent/
    assert_select "tbody", { text: /successful-agent/, count: 0 }
  end

  test "nil cost is unmeasured and is not displayed as zero cost" do
    create_run(agent_name: "measured-agent", cost_usd: 0.25)
    create_run(agent_name: "unmeasured-agent", cost_usd: nil)

    login_as(@admin)
    get admin_agent_runs_path
    assert_response :success
    assert_includes response.body, "$0.2500"
    assert_includes response.body, "집계 1건 / 미집계 1건"
    assert_select "tr", text: /unmeasured-agent/ do
      assert_select "td", text: "—"
    end
  end

  private

  def user_for(email, role)
    user = User.find_or_initialize_by(email: email)
    user.assign_attributes(name: "Agent Runs #{role}", password: "password123", role: role, active: true)
    user.save!
    user
  end

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def create_run(agent_name:, status: "success", started_at: Time.current, cost_usd: nil, error_message: nil)
    AgentRun.create!(
      agent_name: agent_name,
      kind: "service",
      model: "rule-only",
      status: status,
      started_at: started_at,
      finished_at: status == "running" ? nil : started_at + 1.second,
      duration_ms: status == "running" ? nil : 1000,
      cost_usd: cost_usd,
      error_message: error_message
    )
  end
end
