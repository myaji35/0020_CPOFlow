# frozen_string_literal: true

require "test_helper"

class CpoAgent::AutoActionServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by!(email: "auto_action_test@example.com") do |u|
      u.name = "Auto Action Tester"; u.password = "password123"; u.role = :member
    end
    @supplier = Supplier.find_or_create_by!(name: "AutoAction Supplier") do |s|
      s.code = "AACT#{SecureRandom.hex(2)}"
    end
    @order = Order.create!(
      title:         "AutoAction Test Order #{SecureRandom.hex(4)}",
      status:        :new_rfq,
      customer_name: "Test Customer",
      user:          @user,
      supplier:      @supplier
    )
    @insight = AgentInsight.create!(
      order:        @order,
      insight_type: "price_comparison",
      title:        "테스트 인사이트",
      body:         "테스트 내용"
    )
  end

  def teardown
    AgentInsight.where(order: @order).destroy_all
    Comment.where(commentable: @order).destroy_all rescue nil
    @order.destroy if Order.exists?(@order.id)
    @supplier.destroy if Supplier.exists?(@supplier.id)
  end

  test "execute — user nil 시 조기 반환 (에러 없음)" do
    svc = CpoAgent::AutoActionService.new(@order, @insight, nil)
    assert_nothing_raised { svc.execute }
  end

  test "execute — auto_mode false 시 아무 동작 없음" do
    # AgentTrustLevel.auto_mode? = false이면 execute는 nil 반환
    AgentTrustLevel.find_or_create_by(user: @user, insight_type: "price_comparison")
                   .update!(auto_mode: false)
    svc = CpoAgent::AutoActionService.new(@order, @insight, @user)
    result = svc.execute
    assert_nil result
  end

  test "클래스 메서드 execute 존재" do
    assert CpoAgent::AutoActionService.respond_to?(:execute)
  end
end
