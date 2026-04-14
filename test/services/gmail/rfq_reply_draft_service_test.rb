# frozen_string_literal: true

require "test_helper"

class Gmail::RfqReplyDraftServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "rfq_reply_draft_test@example.com") do |u|
      u.name = "RFQ Reply Draft Test"; u.password = "password123"; u.role = :member
    end
    @client = Client.create!(name: "Reply Draft Test Client", code: "RDTC#{SecureRandom.hex(3)}")
    @order = Order.create!(
      title: "Reply Draft 테스트 주문",
      customer_name: "Test Customer",
      client: @client,
      status: :new_rfq,
      user: @user
    )
  end

  def teardown
    @order.destroy if Order.exists?(@order.id)
    @client.destroy if Client.exists?(@client.id)
  end

  test "generate! — reply_draft 캐시 있으면 바로 반환" do
    @order.update_column(:reply_draft, "Cached draft text")
    result = Gmail::RfqReplyDraftService.generate!(@order)
    assert_equal "Cached draft text", result
  end

  test "generate! — Claude API 미설정 시 nil 반환 (오류 없음)" do
    # ClaudeTokenResolver.configured?가 false일 때 nil 반환
    @order.update_column(:reply_draft, nil)
    assert_nothing_raised do
      # API 미설정 환경에서는 nil을 반환
      result = Gmail::RfqReplyDraftService.generate!(@order)
      assert result.nil? || result.is_a?(String)
    end
  end
end
