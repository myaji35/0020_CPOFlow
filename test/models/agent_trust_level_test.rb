# frozen_string_literal: true

require "test_helper"

class AgentTrustLevelTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "agent_trust_model_test@example.com") do |u|
      u.name = "Agent Trust Model Test"; u.password = "password123"; u.role = :member
    end
  end

  def teardown
    AgentTrustLevel.where(user: @user).destroy_all
  end

  test "find_or_create_by — 동일 user + insight_type 중복 생성 안 됨" do
    level1 = AgentTrustLevel.find_or_create_by(user: @user, insight_type: "rfq_auto")
    level2 = AgentTrustLevel.find_or_create_by(user: @user, insight_type: "rfq_auto")
    assert_equal level1.id, level2.id
  end

  test "auto_mode 토글 — false → true" do
    level = AgentTrustLevel.find_or_create_by(user: @user, insight_type: "email_classification")
    level.update!(auto_mode: false)
    level.update!(auto_mode: !level.auto_mode)
    assert level.reload.auto_mode
  end

  test "belongs_to user" do
    level = AgentTrustLevel.find_or_create_by(user: @user, insight_type: "due_date_risk")
    assert_equal @user, level.user
  end
end
