# frozen_string_literal: true

require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "projects_ctrl_test@example.com") do |u|
      u.name = "Projects Test User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)
    @client = Client.create!(name: "Test Client for Projects", code: "CLI-PROJ-#{SecureRandom.hex(4)}", country: "KR")
    @project = Project.create!(name: "Test Project Alpha", client: @client, status: :active)
  end

  def teardown
    @project.destroy if Project.exists?(@project.id)
    @client.destroy if Client.exists?(@client.id)
  end

  test "projects index 200" do
    get projects_path
    assert_response :success
  end

  test "projects index — 현장명 표시" do
    get projects_path
    assert_match "Test Project Alpha", response.body
  end

  test "projects show 200" do
    get project_path(@project)
    assert_response :success
  end

  test "new project form 200" do
    get new_project_path
    assert_response :success
  end

  test "projects create — 성공" do
    assert_difference("Project.count", 1) do
      post projects_path, params: { project: { name: "New Project Beta", client_id: @client.id, status: :active } }
    end
    Project.find_by(name: "New Project Beta")&.destroy
  end

  test "projects create — name 없으면 실패" do
    assert_no_difference("Project.count") do
      post projects_path, params: { project: { name: "", client_id: @client.id, status: :active } }
    end
  end

  test "projects update — name 변경" do
    patch project_path(@project), params: { project: { name: "Updated Project" } }
    @project.reload
    assert_equal "Updated Project", @project.name
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
