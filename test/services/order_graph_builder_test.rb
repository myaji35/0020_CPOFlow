require "test_helper"

class OrderGraphBuilderTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "gb@test.com", password: "password123", name: "GB")
    @client = Client.create!(name: "GB Client", code: "GBC-#{SecureRandom.hex(3)}", country: "KR", active: true)
    @rfq = Order.create!(user: @user, client: @client, title: "RFQ", customer_name: "GB Cust", reference_no: "GB-001", status: :new_rfq)
    @po  = Order.create!(user: @user, client: @client, title: "PO",  customer_name: "GB Cust", reference_no: "GB-001", status: :new_po, parent_order: @rfq)
    OrderLink.find_or_create_by!(source: @rfq, target: @po, relation: "confirmed_to") do |l|
      l.status = "confirmed"
      l.confidence = 1.0
    end
  end

  test "depth 1 — root와 직접 연결만 포함" do
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    node_ids = g[:nodes].map { |n| n[:id] }
    assert_includes node_ids, "Order:#{@rfq.id}"
    assert_includes node_ids, "Order:#{@po.id}"
    rfq_node = g[:nodes].find { |n| n[:id] == "Order:#{@rfq.id}" }
    assert_equal true, rfq_node[:current]
  end

  test "depth 2 — 손자 노드 포함" do
    grand = Order.create!(user: @user, client: @client, title: "GRN", customer_name: "GB Cust", reference_no: "GB-001", status: :get_grn, parent_order: @po)
    OrderLink.find_or_create_by!(source: @po, target: grand, relation: "delivered_as") do |l|
      l.status = "confirmed"
      l.confidence = 1.0
    end
    g = OrderGraphBuilder.new(@rfq, depth: 2).call
    assert_includes g[:nodes].map { |n| n[:id] }, "Order:#{grand.id}"
  end

  test "MAX_DEPTH=3 강제 — 99 입력해도 3으로 cap" do
    builder = OrderGraphBuilder.new(@rfq, depth: 99)
    assert_equal 3, builder.send(:depth)
  end

  test "reference_no 가상 링크 합성 — 같은 reference_no 노드 자동 연결" do
    Order.create!(user: @user, client: @client, title: "Sibling", customer_name: "GB Cust", reference_no: "GB-001", status: :new_rfq)
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    virtual_refs = g[:edges].select { |e| e[:virtual] && e[:relation] == "references" }
    assert virtual_refs.any?, "reference_no 가상 엣지 없음 (총 #{g[:edges].size}개 엣지)"
  end

  test "FK 가상 링크 — Client 가상 노드 합성" do
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    assert g[:nodes].any? { |n| n[:type] == "Client" }, "Client 가상 노드 없음"
  end

  test "명시 링크 우선 — 같은 (source,target,relation) 가상 링크는 생략" do
    g = OrderGraphBuilder.new(@rfq, depth: 1).call
    confirmed_to_edges = g[:edges].select do |e|
      e[:relation] == "confirmed_to" && e[:from] == "Order:#{@rfq.id}" && e[:to] == "Order:#{@po.id}"
    end
    assert_equal 1, confirmed_to_edges.size
    assert_equal false, confirmed_to_edges.first[:virtual]
  end
end
