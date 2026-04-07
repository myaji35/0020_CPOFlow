# frozen_string_literal: true

require "test_helper"

class TeamControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.find_or_create_by(email: "team_admin_test@example.com") do |u|
      u.name     = "Team Admin Test"
      u.password = "password123"
      u.role     = :admin
    end
    @admin.update!(role: :admin)

    @member = User.find_or_create_by(email: "team_member_test@example.com") do |u|
      u.name     = "Team Member Test"
      u.password = "password123"
      u.role     = :member
    end

    login_as(@admin)
  end

  # ─── index ───────────────────────────────

  test "team index 200 응답" do
    get team_index_path
    assert_response :success
  end

  test "team index — 팀원 목록 표시" do
    get team_index_path
    assert_response :success
    assert_match @admin.name, response.body
  end

  test "team index — branch 필터 파라미터 동작" do
    get team_index_path(branch: "seoul")
    assert_response :success
  end

  test "team index — abu_dhabi 필터 동작" do
    get team_index_path(branch: "abu_dhabi")
    assert_response :success
  end

  # ─── show ────────────────────────────────

  test "team show 200 응답" do
    get team_path(@admin)
    assert_response :success
  end

  test "team show — 팀원 이름 표시" do
    get team_path(@admin)
    assert_response :success
    assert_match @admin.name, response.body
  end

  # ─── update_role ─────────────────────────

  test "update_role — admin이 역할 변경 성공" do
    patch update_role_team_path(@member), params: { role: "manager" }
    assert_redirected_to team_index_path
    @member.reload
    assert_equal "manager", @member.role
    # 원복
    @member.update!(role: :member)
  end

  test "update_role — admin이 viewer로 역할 변경 성공" do
    target = User.find_or_create_by(email: "team_viewer_test@example.com") do |u|
      u.name     = "Viewer Target"
      u.password = "password123"
      u.role     = :member
    end

    patch update_role_team_path(target), params: { role: "viewer" }
    assert_redirected_to team_index_path
    target.reload
    assert_equal "viewer", target.role

    target.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
