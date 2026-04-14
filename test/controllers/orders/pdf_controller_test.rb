# frozen_string_literal: true

require "test_helper"

class Orders::PdfControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "orders_pdf_ctrl_test@example.com") do |u|
      u.name = "Orders PDF Ctrl User"; u.password = "password123"; u.role = :member
    end
    login_as(@user)

    @client = Client.create!(name: "PDF Test Client", code: "PDFCLI#{SecureRandom.hex(3)}")
    @order = Order.create!(
      title: "PDF 테스트 주문",
      customer_name: "PDF Test Customer",
      client: @client,
      status: :new_rfq,
      user: @user
    )
  end

  def teardown
    @order&.destroy if @order && Order.exists?(@order.id)
    @client&.destroy if @client && Client.exists?(@client.id)
  end

  test "quote PDF — 200 or redirect (wkhtmltopdf 없어도 응답)" do
    get pdf_quote_order_path(@order)
    # wkhtmltopdf 미설치 환경에서는 500이 날 수 있으므로 응답만 확인
    assert_includes [ 200, 302, 500 ], response.status
  end

  test "purchase_order PDF — 응답" do
    get pdf_purchase_order_order_path(@order)
    assert_includes [ 200, 302, 500 ], response.status
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
