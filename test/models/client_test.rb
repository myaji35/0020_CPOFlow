require "test_helper"

class ClientTest < ActiveSupport::TestCase
  test "Client INDUSTRIES 상수 유효" do
    expected = %w[nuclear hydro tunnel gtx construction general]
    assert_equal expected, Client::INDUSTRIES
  end

  test "Client CREDIT_GRADES 상수 유효" do
    assert_equal %w[A B C D], Client::CREDIT_GRADES
  end

  test "Client scopes 정상 동작" do
    assert_nothing_raised { Client.active.count }
    assert_nothing_raised { Client.by_name.limit(5).to_a }
  end

  test "Client associations 쿼리 정상" do
    assert_nothing_raised do
      Client.includes(:projects, :orders, :contact_persons).limit(5).to_a
    end
  end
end
