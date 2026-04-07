require "test_helper"

class ClientExtendedTest < ActiveSupport::TestCase
  test "Client: name 없으면 errors 발생" do
    client = Client.new(code: "TC00", country: "AE")
    client.valid?
    assert client.errors[:name].any?
  end

  test "Client: code 없으면 errors 발생" do
    client = Client.new(name: "Test", country: "AE")
    client.valid?
    assert client.errors[:code].any?
  end

  test "Client: country는 DB 기본값(AE)으로 자동 설정됨" do
    client = Client.new(name: "Test", code: "TC00X")
    assert_equal "AE", client.country
  end

  test "Client: 유효하지 않은 industry이면 invalid" do
    client = Client.new(name: "Test", code: "TC01", country: "AE", industry: "invalid")
    assert_not client.valid?
  end

  test "Client: 유효한 industry이면 valid" do
    client = Client.new(name: "Test", code: "TC02", country: "AE", industry: "nuclear")
    client.valid?
    assert client.errors[:industry].empty?
  end

  test "Client: 유효하지 않은 credit_grade이면 invalid" do
    client = Client.new(name: "Test", code: "TC03", country: "AE", credit_grade: "Z")
    assert_not client.valid?
  end

  test "industry_label: nuclear이면 원전" do
    client = Client.new(name: "Test", code: "TC04", country: "AE", industry: "nuclear")
    assert_equal "원전", client.industry_label
  end

  test "industry_label: 미지원이면 그대로" do
    client = Client.new(name: "Test", code: "TC05", country: "AE", industry: "other")
    assert_equal "other", client.industry_label
  end

  test "total_order_value: 레코드 없어도 예외 없음" do
    assert_nothing_raised do
      Client.active.each { |c| c.total_order_value }
    end
  end

  test "active_orders_count: 레코드 없어도 예외 없음" do
    assert_nothing_raised do
      Client.active.limit(3).each { |c| c.active_orders_count }
    end
  end

  test "INDUSTRIES 상수 포함 확인" do
    %w[nuclear hydro tunnel gtx construction general].each do |ind|
      assert_includes Client::INDUSTRIES, ind
    end
  end

  test "CREDIT_GRADES 상수 확인" do
    assert_includes Client::CREDIT_GRADES, "A"
    assert_includes Client::CREDIT_GRADES, "D"
  end

  test "active scope 동작" do
    assert_nothing_raised { Client.active.count }
  end

  test "by_name scope 동작" do
    assert_nothing_raised { Client.by_name.limit(5).to_a }
  end
end
