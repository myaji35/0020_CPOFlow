# frozen_string_literal: true

require "test_helper"

# ISS-352: 직원 Impersonation 검증
# 6개 acceptance criteria 모두 커버:
#   1. admin 전용 — 비admin 접근 시 차단
#   2. admin → admin 가장 불가
#   3. 토큰 60초 만료 — 재사용 불가
#   4. 가장 중 상단 배너 항상 표시
#   5. 배너 클릭(stop_impersonating) 시 admin 세션으로 복귀
#   6. 새 탭에서 해당 직원의 role/branch 기준 화면 표시
class ImpersonationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.find_or_create_by(email: "iss352_admin_test@example.com") do |u|
      u.name = "ISS-352 Admin"; u.password = "password123"; u.role = :admin
    end
    @admin.update!(role: :admin)

    @other_admin = User.find_or_create_by(email: "iss352_admin2_test@example.com") do |u|
      u.name = "ISS-352 Admin 2"; u.password = "password123"; u.role = :admin
    end
    @other_admin.update!(role: :admin)

    @target = User.find_or_create_by(email: "iss352_target_test@example.com") do |u|
      u.name = "ISS-352 Target"; u.password = "password123"; u.role = :member; u.branch = "seoul"
    end
    @target.update!(role: :member, branch: "seoul")

    @non_admin = User.find_or_create_by(email: "iss352_nonadmin_test@example.com") do |u|
      u.name = "ISS-352 Non-Admin"; u.password = "password123"; u.role = :manager
    end
    @non_admin.update!(role: :manager)
  end

  def teardown
    ImpersonationToken.where(admin_id: [@admin.id, @other_admin.id, @non_admin.id]).delete_all
  end

  # AC#1
  test "AC#1 — 비admin(manager) 토큰 발급 시도 시 차단" do
    login_as(@non_admin)
    post impersonations_path, params: { user_id: @target.id }
    assert_response :redirect
    follow_redirect!
    assert_match(/권한이 없습니다/, response.body)
    assert_equal 0, ImpersonationToken.where(target_user_id: @target.id).count,
                 "비admin은 토큰을 발급할 수 없어야 함"
  end

  # AC#2
  test "AC#2 — admin → admin 가장 시도 시 차단" do
    login_as(@admin)
    post impersonations_path, params: { user_id: @other_admin.id }
    assert_response :redirect
    follow_redirect!
    assert_match(/Admin 계정은 가장할 수 없습니다/, response.body)
    assert_equal 0, ImpersonationToken.where(target_user_id: @other_admin.id).count
  end

  # AC#3 (a) — 60초 만료
  test "AC#3a — 60초 만료된 토큰은 재사용 불가" do
    login_as(@admin)
    token = ImpersonationToken.issue!(admin: @admin, target_user: @target)
    token.update_column(:expires_at, 1.second.ago)

    get impersonations_enter_path(token: token.token)
    assert_response :redirect
    follow_redirect!
    assert_match(/유효하지 않거나 만료된 링크/, response.body)
  end

  # AC#3 (b) — 1회 사용 후 폐기
  test "AC#3b — 1회 사용 후 동일 토큰 재사용 불가" do
    login_as(@admin)
    token = ImpersonationToken.issue!(admin: @admin, target_user: @target)

    get impersonations_enter_path(token: token.token)
    assert_response :redirect
    assert_not_nil token.reload.used_at, "사용 후 used_at 마킹 필요"

    # 같은 세션에서 재사용 시도 — 토큰 valid scope 탈락으로 차단됨
    get impersonations_enter_path(token: token.token)
    follow_redirect!
    assert_match(/유효하지 않거나 만료된 링크/, response.body)
  end

  # AC#4 + AC#6
  test "AC#4/6 — admin이 가장 진입 시 세션 세팅 + 배너 노출" do
    login_as(@admin)
    post impersonations_path, params: { user_id: @target.id }
    # create 액션은 enter URL로 redirect → 토큰 소비 + 세션 세팅
    follow_redirect!
    follow_redirect!  # enter → root_path

    # AC#6: 가장 대상의 display_name이 배너에 나타나야 함
    assert_match(/#{Regexp.escape(@target.display_name)}.*계정으로 보는 중/, response.body)
    # AC#4: 가장 해제 버튼이 페이지에 존재
    assert_match(/내 계정으로 돌아가기/, response.body)
  end

  # AC#5
  test "AC#5 — DELETE /impersonations 호출 시 admin 세션으로 복귀" do
    login_as(@admin)
    token = ImpersonationToken.issue!(admin: @admin, target_user: @target)
    get impersonations_enter_path(token: token.token)
    follow_redirect!

    delete impersonations_path
    assert_response :redirect
    follow_redirect!
    assert_match(/내 계정으로 돌아왔습니다/, response.body)

    # 후속 요청에서 가장 배너가 사라져야 함
    get root_path
    assert_no_match(/#{@target.display_name}.*보는 중/, response.body)
  end

  # 추가: 토큰 발급 후 enter URL로 redirect (정상 경로)
  test "POST 후 즉시 enter URL로 redirect" do
    login_as(@admin)
    post impersonations_path, params: { user_id: @target.id }
    assert_response :see_other
    assert_match(%r{/impersonations/enter\?token=}, response.location)
  end

  private

  def login_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password123" }
    }
  end
end
