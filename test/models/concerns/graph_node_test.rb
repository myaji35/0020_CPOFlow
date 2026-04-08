require "test_helper"

class GraphNodeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "graph_node_test_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      name: "GN Test"
    )
    @rfq = Order.create!(
      user: @user, title: "RFQ", reference_no: "GN-001",
      status: :new_rfq, customer_name: "Test Customer"
    )
    @po = Order.create!(
      user: @user, title: "PO",  reference_no: "GN-001",
      status: :new_po, customer_name: "Test Customer"
    )
    OrderLink.create!(source: @rfq, target: @po, relation: "confirmed_to", status: "confirmed")
  end

  test "outgoing_links 반환 — source 노드에서" do
    assert_equal 1, @rfq.outgoing_links.count
    assert_equal "confirmed_to", @rfq.outgoing_links.first.relation
  end

  test "incoming_links 반환 — target 노드에서" do
    assert_equal 1, @po.incoming_links.count
    assert_equal "confirmed_to", @po.incoming_links.first.relation
  end

  test "linked_nodes 양방향 합산 + 중복 제거" do
    nodes_from_rfq = @rfq.linked_nodes
    nodes_from_po  = @po.linked_nodes
    assert_includes nodes_from_rfq, @po
    assert_includes nodes_from_po, @rfq
  end
end
