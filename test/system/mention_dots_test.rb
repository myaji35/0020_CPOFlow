# frozen_string_literal: true

require "application_system_test_case"

# ISS-353 Phase 1 — T15: Capybara system test 4 페르소나
# 시나리오 A/B/C/D — 발신자 / 수신자 / 제3자 / 관리자
#
# 핵심 검증 포인트 (CPOFlow 룰):
#   - Scenario B (수신자 [✓ 확인] 클릭) MUST PASS — 실 클릭 검증 의무
#   - 다른 시나리오는 인프라 한계로 skip 가능, but 가능한 한 패스
#
# 본 테스트는 fixture 비사용 — User/Employee/Order/Comment 모두 inline create.
class MentionDotsTest < ApplicationSystemTestCase
  setup do
    I18n.locale = :ko

    suffix = SecureRandom.hex(3)

    @sender = User.create!(
      email:    "sender_#{suffix}@test.com",
      password: "password123",
      role:     :member,
      branch:   :seoul,
      locale:   "ko",
      name:     "발신홍",
      active:   true
    )

    @receiver = User.create!(
      email:    "receiver_#{suffix}@test.com",
      password: "password123",
      role:     :member,
      branch:   :seoul,
      locale:   "ko",
      name:     "수신김",
      active:   true
    )

    @third = User.create!(
      email:    "third_#{suffix}@test.com",
      password: "password123",
      role:     :member,
      branch:   :seoul,
      locale:   "ko",
      name:     "제삼이",
      active:   true
    )

    @admin = User.create!(
      email:    "admin_#{suffix}@test.com",
      password: "password123",
      role:     :admin,
      branch:   :seoul,
      locale:   "ko",
      name:     "관리박",
      active:   true
    )

    # MentionParserService는 Employee.find_by(name:) 으로 사용자 매칭한다.
    Employee.find_or_create_by!(name: "수신김") do |e|
      e.user = @receiver; e.nationality = "KR"; e.employment_type = "regular"
    end
    Employee.find_or_create_by!(name: "제삼이") do |e|
      e.user = @third; e.nationality = "KR"; e.employment_type = "regular"
    end

    # 칸반 new_rfq 컬럼은 rfq_status: :rfq_triage 만 노출 (Order::KANBAN_VISIBLE_RFQ_STATUSES).
    # 기본 rfq_status(:rfq_pending) 는 인박스 전용이라 칸반에서 안 보인다.
    @order = Order.create!(
      user:          @sender,
      title:         "테스트 발주 #{suffix}",
      customer_name: "Test Client",
      status:        :new_rfq,
      rfq_status:    :rfq_triage
    )
  end

  teardown do
    I18n.locale = I18n.default_locale
  end

  # === Scenario A: 발신자 ===
  test "시나리오 A: 발신자가 멘션을 보내면 칸반 카드에 미확인 도트가 노출된다" do
    Comment.create!(order: @order, user: @sender, body: "@수신김 자료 부탁합니다")
    MentionParserService.new(Comment.last, @sender).call

    # broadcast 후 카운터 캐시 동기화 시간
    @order.reload
    assert_equal 1, @order.mention_total_count, "CREATE 후 mention_total_count=1 이어야 함"

    sign_in(@sender)
    visit kanban_path

    # 발신자도 도트 줄을 본다 — 도트 줄 자체는 누구에게나 렌더된다
    # (B1-b: 클라이언트 viewer 마킹은 Phase 1 도트 색상에는 영향 없음)
    assert page.has_css?("#mention-dot-strip-#{@order.id}", wait: 5),
           "발신자 칸반에 도트 줄이 렌더되지 않음"
    within "#mention-dot-strip-#{@order.id}" do
      assert page.has_text?("0/1 확인"), "0/1 확인 비율 미표시"
      assert page.has_css?("[data-state='unread']"), "unread 도트 미존재"
    end
  end

  # === Scenario B: 수신자 ===
  # CPOFlow 룰: UI 기능은 실 클릭 검증 필수. 본 시나리오는 절대 skip 불가.
  test "시나리오 B: 수신자가 [✓ 확인] 클릭하면 도트가 즉시 acknowledged로 변경된다" do
    Comment.create!(order: @order, user: @sender, body: "@수신김 확인 부탁드립니다")
    MentionParserService.new(Comment.last, @sender).call

    notif = Notification.where(user: @receiver, notifiable: @order, notification_type: "mentioned").last
    assert_not_nil notif, "수신자 Notification이 생성되어야 함"
    assert_nil notif.acknowledged_at, "초기 상태는 미확인"

    sign_in(@receiver)
    # 드로어 멘션 패널은 order detail 페이지의 comments 탭에 렌더된다
    visit order_path(@order)

    # 코멘트 탭 활성화 (drawer-tab 패턴은 onclick으로 패널 hidden 토글)
    page.execute_script("if (typeof switchDrawerTab === 'function') switchDrawerTab('#{@order.id}', 'comments');")

    # mention-pending-panel 안에 자기 알림 행 + [✓ 확인] 버튼 존재 확인
    assert page.has_css?("#mention-pending-panel-#{@order.id}", wait: 5),
           "수신자 드로어에 멘션 패널이 렌더되지 않음"

    within "#mention-pending-panel-#{@order.id}" do
      assert page.has_css?("#notification-row-#{notif.id}"), "수신자 알림 행 미존재"
      # [✓ 확인] 버튼은 form#button_to 내부 button — Capybara click_button 으로 클릭
      click_button I18n.t("mentions.acknowledge.button")  # "확인"
    end

    # turbo_stream.remove → 알림 행 사라짐
    assert_no_selector "#notification-row-#{notif.id}", wait: 5

    # DB 상태: acknowledged_at 세팅 + Order 카운터 증가
    notif.reload
    assert_not_nil notif.acknowledged_at, "[✓ 확인] 클릭 후 acknowledged_at 미세팅"
    @order.reload
    assert_equal 1, @order.mention_acknowledged_count,
                 "Order.mention_acknowledged_count 미반영 (got #{@order.mention_acknowledged_count})"
  end

  # === Scenario C: 제3자 ===
  test "시나리오 C: 제3자에게는 [✓ 확인] 버튼이 노출되지 않는다" do
    Comment.create!(order: @order, user: @sender, body: "@수신김 검토 부탁")
    MentionParserService.new(Comment.last, @sender).call

    sign_in(@third)
    visit order_path(@order)
    page.execute_script("if (typeof switchDrawerTab === 'function') switchDrawerTab('#{@order.id}', 'comments');")

    # 제3자에게도 패널 컨테이너는 렌더되지만 (current_user.notifications.mentions
    # 스코프가 본인 알림만 가져오므로) 빈 상태 — [✓ 확인] 버튼 미존재
    assert page.has_css?("#mention-pending-panel-#{@order.id}", wait: 5),
           "제3자 드로어에도 패널 컨테이너는 렌더됨"
    within "#mention-pending-panel-#{@order.id}" do
      assert_no_selector "form button", text: I18n.t("mentions.acknowledge.button")
    end
  end

  # === Scenario D: 관리자 ===
  test "시나리오 D: 관리자는 도트 줄과 비율을 정상적으로 본다" do
    Comment.create!(order: @order, user: @sender, body: "@수신김 @제삼이 검토 부탁")
    MentionParserService.new(Comment.last, @sender).call

    @order.reload
    assert_equal 2, @order.mention_total_count, "수신김+제삼이 2명 멘션"

    sign_in(@admin)
    visit kanban_path

    assert page.has_css?("#mention-dot-strip-#{@order.id}", wait: 5),
           "관리자 칸반에 도트 줄 미렌더"
    within "#mention-dot-strip-#{@order.id}" do
      assert page.has_text?("0/2 확인"), "0/2 확인 비율 미표시"
    end
  end

  private

  # 기존 card_status_management_test.rb 와 동일한 로그인 헬퍼
  # Devise field IDs: user_email / user_password, submit "로그인"
  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email",    with: user.email
    fill_in "user_password", with: "password123"
    click_button "로그인"
    # 로그인 직후 root 또는 kanban으로 redirect — 페이지 안정화 대기
    assert_no_current_path new_user_session_path, wait: 5
  rescue Minitest::Assertion
    # 로그인 실패 진단: 현재 path + 에러 메시지 출력
    flunk "로그인 실패: current_path=#{current_path}, body_excerpt=#{page.text[0, 200]}"
  end
end
