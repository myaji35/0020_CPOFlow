# frozen_string_literal: true

require "test_helper"

class InboxControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "inbox_ctrl_test@example.com") do |u|
      u.name = "Inbox Test User"; u.password = "password123"; u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)
  end

  test "inbox index 200" do
    get inbox_path
    assert_response :success
  end

  test "inbox index — filter all" do
    get inbox_path, params: { filter: "all" }
    assert_response :success
  end

  test "inbox index — filter rfq" do
    get inbox_path, params: { filter: "rfq" }
    assert_response :success
  end

  test "inbox index — filter uncertain" do
    get inbox_path, params: { filter: "uncertain" }
    assert_response :success
  end

  test "inbox index — filter converted" do
    get inbox_path, params: { filter: "converted" }
    assert_response :success
  end

  test "inbox index — 검색 파라미터" do
    get inbox_path, params: { q: "test search" }
    assert_response :success
  end

  test "inbox index — 페이지네이션" do
    get inbox_path, params: { page: 2 }
    assert_response :success
  end

  test "destroy — archived_at 설정 + redirect" do
    client = Client.create!(name: "Inbox Del Client", code: "IDCL#{SecureRandom.hex(3)}")
    order = Order.create!(
      title: "Inbox Del Test",
      customer_name: "Del Customer",
      client: client,
      status: :new_rfq,
      user: @user,
      original_email_from: "sender@example.com",
      original_email_subject: "Test"
    )

    assert_nil order.archived_at
    delete delete_inbox_email_path(order)
    assert_response :redirect
    assert order.reload.archived_at.present?

    # archived 는 inbox에 다시 보이지 않음
    get inbox_path
    assert_response :success
    assert_not_includes response.body, "Inbox Del Test"

    order.reload.destroy
    client.destroy
  end

  test "destroy — turbo_stream 응답 시 row 제거" do
    client = Client.create!(name: "Inbox TS Client", code: "ITCL#{SecureRandom.hex(3)}")
    order = Order.create!(
      title: "Inbox TS Test",
      customer_name: "TS Customer",
      client: client,
      status: :new_rfq,
      user: @user,
      original_email_from: "sender@example.com"
    )

    delete delete_inbox_email_path(order), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, "email-item-#{order.id}"

    order.reload.destroy
    client.destroy
  end

  test "bulk_trash — 여러 건 archived 처리 + JSON 응답" do
    client = Client.create!(name: "Bulk Trash Client", code: "BTCL#{SecureRandom.hex(3)}")
    orders = 3.times.map do |i|
      Order.create!(
        title: "Bulk Trash #{i}",
        customer_name: "Bulk C#{i}",
        client: client,
        status: :new_rfq,
        user: @user,
        original_email_from: "sender#{i}@example.com"
      )
    end

    post inbox_bulk_trash_path, params: { order_ids: orders.map(&:id) }, as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert_equal 3, body["count"]

    orders.each { |o| assert o.reload.archived_at.present?, "ord #{o.id} should be archived" }

    orders.each { |o| o.reload.destroy }
    client.destroy
  end

  test "bulk_trash — order_ids 빈 배열이면 count 0" do
    post inbox_bulk_trash_path, params: { order_ids: [] }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert_equal 0, body["count"]
  end

  # ── show ──────────────────────────────────────────────────────────────
  test "show — 존재하는 order id" do
    client = Client.create!(name: "Show Cl", code: "SHWCL#{SecureRandom.hex(2)}")
    order = Order.create!(
      title: "Show Test Order", customer_name: "Show C",
      client: client, status: :new_rfq, user: @user
    )
    get inbox_email_path(order)
    assert_response :success
    order.reload.destroy; client.destroy
  end

  test "show — 존재하지 않는 id면 inbox redirect" do
    get inbox_email_path(id: 0)
    assert_redirected_to inbox_path
  end

  # ── convert_to_order ──────────────────────────────────────────────────
  test "convert_to_order — rfq_triage 상태일 때 칸반으로 이동" do
    client = Client.create!(name: "Conv Cl", code: "CNVCL#{SecureRandom.hex(2)}")
    order = Order.create!(
      title: "Convert Test", customer_name: "Conv C",
      client: client, status: :new_rfq, rfq_status: :rfq_triage, user: @user
    )
    post convert_email_to_order_path(order)
    assert_response :redirect
    order.reload.destroy; client.destroy
  end

  test "convert_to_order — rfq_excluded 상태는 차단" do
    client = Client.create!(name: "Conv Ex Cl", code: "CVXCL#{SecureRandom.hex(2)}")
    order = Order.create!(
      title: "Convert Blocked", customer_name: "Ex C",
      client: client, status: :new_rfq, rfq_status: :rfq_excluded, user: @user
    )
    post convert_email_to_order_path(order)
    assert_response :redirect
    order.reload.destroy; client.destroy
  end

  # ── bulk_delete ───────────────────────────────────────────────────────
  test "bulk_delete — new_rfq 건들 rfq_excluded 처리" do
    client = Client.create!(name: "BDel Cl", code: "BDELCL#{SecureRandom.hex(2)}")
    orders = 2.times.map do |i|
      Order.create!(title: "BDel #{i}", customer_name: "C#{i}",
                    client: client, status: :new_rfq, rfq_status: :rfq_pending, user: @user)
    end
    post inbox_bulk_delete_path, params: { order_ids: orders.map(&:id) }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    orders.each { |o| o.reload.destroy }; client.destroy
  end

  test "bulk_delete — 빈 배열" do
    post inbox_bulk_delete_path, params: { order_ids: [] }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body["count"]
  end

  # ── bulk_to_kanban ────────────────────────────────────────────────────
  test "bulk_to_kanban — eligible 건 이동" do
    client = Client.create!(name: "BTK Cl", code: "BTKCL#{SecureRandom.hex(2)}")
    orders = 2.times.map do |i|
      Order.create!(title: "BTK #{i}", customer_name: "K#{i}",
                    client: client, status: :new_rfq, rfq_status: :rfq_triage, user: @user)
    end
    post inbox_bulk_to_kanban_path, params: { order_ids: orders.map(&:id) }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    orders.each { |o| o.reload.destroy }; client.destroy
  end

  test "bulk_to_kanban — 빈 배열" do
    post inbox_bulk_to_kanban_path, params: { order_ids: [] }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body["count"]
  end

  # ── bulk_restore ──────────────────────────────────────────────────────
  test "bulk_restore — rfq_excluded → rfq_pending 복원" do
    client = Client.create!(name: "BRest Cl", code: "BRSTCL#{SecureRandom.hex(2)}")
    orders = 2.times.map do |i|
      Order.create!(title: "BRest #{i}", customer_name: "R#{i}",
                    client: client, status: :new_rfq, rfq_status: :rfq_excluded, user: @user)
    end
    post inbox_bulk_restore_path, params: { order_ids: orders.map(&:id) }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    orders.each { |o| assert_equal "rfq_pending", o.reload.rfq_status }
    orders.each { |o| o.reload.destroy }; client.destroy
  end

  # ── sync ──────────────────────────────────────────────────────────────
  test "sync — 연결된 계정 없으면 422" do
    post inbox_sync_path, as: :json
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "error", body["status"]
  end

  # ── translate ─────────────────────────────────────────────────────────
  test "translate — 존재하지 않는 id면 404" do
    get inbox_translate_path(id: 0), as: :json
    assert_response :not_found
  end

  test "translate — 존재하는 order는 JSON 반환" do
    client = Client.create!(name: "Trans Cl", code: "TRNCL#{SecureRandom.hex(2)}")
    order = Order.create!(
      title: "Trans Test", customer_name: "Trans C",
      client: client, status: :new_rfq, user: @user,
      original_email_subject: "Hello", original_email_body: "Test body"
    )
    get inbox_translate_path(order), as: :json
    assert_response :success
    order.reload.destroy; client.destroy
  end

  # ── feedback ──────────────────────────────────────────────────────────
  test "feedback — 잘못된 verdict는 422" do
    client = Client.create!(name: "FB Cl", code: "FBCL#{SecureRandom.hex(2)}")
    order = Order.create!(title: "FB Test", customer_name: "FB C",
                          client: client, status: :new_rfq, user: @user)
    post inbox_feedback_path(order), params: { verdict: "invalid" }, as: :json
    assert_response :unprocessable_entity
    order.reload.destroy; client.destroy
  end

  test "feedback — rejected verdict 처리" do
    client = Client.create!(name: "FB Rej Cl", code: "FBRJCL#{SecureRandom.hex(2)}")
    order = Order.create!(title: "FB Rej Test", customer_name: "FB Rej",
                          client: client, status: :new_rfq, rfq_status: :rfq_pending, user: @user)
    post inbox_feedback_path(order), params: { verdict: "rejected" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert_equal "rejected", body["verdict"]
    order.reload.destroy; client.destroy
  end

  test "feedback — 존재하지 않는 order면 404" do
    post inbox_feedback_path(id: 0), params: { verdict: "confirmed" }, as: :json
    assert_response :not_found
  end

  # ── analyze_link ──────────────────────────────────────────────────────
  test "analyze_link — url 빈값이면 422" do
    post inbox_analyze_link_path, params: { url: "" }, as: :json
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
  end

  test "analyze_link — http가 아닌 url이면 422" do
    post inbox_analyze_link_path, params: { url: "ftp://example.com" }, as: :json
    assert_response :unprocessable_entity
  end

  # ── download_attachment ───────────────────────────────────────────────
  test "download_attachment — 존재하지 않는 order면 403" do
    get inbox_attachment_path(id: 0, blob_key: "nonexistent")
    assert_response :forbidden
  end

  test "download_attachment — order 있지만 blob_key 없으면 404" do
    client = Client.create!(name: "DL Cl", code: "DLCL#{SecureRandom.hex(2)}")
    order = Order.create!(title: "DL Test", customer_name: "DL C",
                          client: client, status: :new_rfq, user: @user)
    get inbox_attachment_path(order, blob_key: "nonexistent_blob_key")
    assert_response :not_found
    order.reload.destroy; client.destroy
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
