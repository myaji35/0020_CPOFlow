# frozen_string_literal: true

require "test_helper"

class Settings::CardStatusesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "settings_cardstatus_test@example.com") do |u|
      u.name = "Settings CardStatus User"
      u.password = "password123"
      u.role = :admin
    end
    @user.update!(role: :admin)
    login_as(@user)

    CardStatus.delete_all
    @urgent = CardStatus.create!(
      key: "urgent", name: "긴급",
      bg_color: "#FFF1F2", border_color: "#FECDD3", text_color: "#991B1B",
      position: 1, is_system: true, is_default: false
    )
    @normal = CardStatus.create!(
      key: "normal", name: "보통",
      bg_color: "#FAFAFA", border_color: "#E5E7EB", text_color: "#374151",
      position: 3, is_system: true, is_default: true
    )
    @vip = CardStatus.create!(
      key: "vip", name: "VIP",
      bg_color: "#F5F3FF", border_color: "#DDD6FE", text_color: "#5B21B6",
      position: 4, is_system: false, is_default: false
    )
    @hold = CardStatus.create!(
      key: "hold", name: "보류",
      bg_color: "#F3F4F6", border_color: "#D1D5DB", text_color: "#4B5563",
      position: 5, is_system: false, is_default: false
    )
  end

  test "POST create valid" do
    assert_difference -> { CardStatus.count }, 1 do
      post settings_card_statuses_path, params: {
        card_status: {
          key: "new_manual", name: "새 상태",
          bg_color: "#EEF2FF", border_color: "#C7D2FE", text_color: "#312E81"
        }
      }
    end
    assert_redirected_to settings_card_statuses_path
  end

  test "PATCH inline_rename updates name" do
    patch inline_rename_settings_card_status_path(@vip), params: { name: "새VIP" }
    assert_response :success
    assert_equal "새VIP", @vip.reload.name
  end

  test "DELETE destroy blocks system status" do
    assert_no_difference -> { CardStatus.count } do
      delete settings_card_status_path(@urgent)
    end
    assert_response :see_other
  end

  test "DELETE destroy blocks in-use status" do
    Order.create!(
      title: "X", customer_name: "A", card_status: @vip,
      status: "new_rfq", user: @user,
      card_status_manually_set_at: Time.current
    )
    assert_no_difference -> { CardStatus.count } do
      delete settings_card_status_path(@vip)
    end
    assert_response :see_other
  end

  test "DELETE destroy succeeds when deletable" do
    @hold.orders.destroy_all
    assert_difference -> { CardStatus.count }, -1 do
      delete settings_card_status_path(@hold)
    end
    assert_redirected_to settings_card_statuses_path
  end

  test "PATCH reorder accepts array" do
    ids = CardStatus.ordered.pluck(:id).reverse
    patch reorder_settings_card_statuses_path, params: { order: ids }
    assert_response :success
    assert_equal ids, CardStatus.ordered.pluck(:id)
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
