require "application_system_test_case"

class CardStatusManagementTest < ApplicationSystemTestCase
  # 프로젝트는 fixture를 기본 로드하지 않고(User는 Devise) User/CardStatus를 직접 생성한다.
  setup do
    @user = User.find_or_create_by(email: "cs-sys@test.com") do |u|
      u.name = "CS Sys"
      u.password = "password123"
      u.role = :admin
    end
    @vip = CardStatus.find_or_create_by(key: "vip") do |cs|
      cs.name = "VIP"
      cs.bg_color = "#F5F3FF"
      cs.border_color = "#DDD6FE"
      cs.text_color = "#5B21B6"
      cs.position = 4
      cs.is_system = false
      cs.is_default = false
      cs.auto_priority = 10
    end
    login_as(@user)
  end

  test "rename via inline edit" do
    visit settings_card_statuses_path
    row = find("[data-cs-id=\"#{@vip.id}\"]")
    within(row) do
      name_el = find("[contenteditable=true]")
      name_el.click
      name_el.send_keys [:control, "a"], :backspace, "VVVIP"
      name_el.send_keys :tab # blur
    end
    sleep 0.5
    assert_equal "VVVIP", @vip.reload.name
  end

  test "delete blocks when in use" do
    Order.create!(user: @user, title: "X", customer_name: "A", status: "new_rfq", card_status: @vip)

    visit settings_card_statuses_path
    row = find("[data-cs-id=\"#{@vip.id}\"]")
    within(row) do
      delete_btn = find("button[title*='사용 중']")
      assert delete_btn.disabled?
    end
  end

  private

  def login_as(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button I18n.t("devise.sessions.new.sign_in", default: "Log in")
  end
end
