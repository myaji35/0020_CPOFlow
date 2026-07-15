require "test_helper"

class OrdersControllerPreviewByRefTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "pbr@test.com") do |u|
      u.name = "PBR"
      u.password = "password123"
      u.role = :member
    end
    login_as(@user)
    @order = Order.create!(
      user: @user, title: "Pre Test",
      customer_name: "C", reference_no: "PBR-2026-0001",
      status: :new_rfq
    )
    Rails.cache.clear
  end

  test "preview_by_ref 200 + 응답에 ref 포함" do
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    assert_response :success
    assert_match(/PBR-2026-0001/, response.body)
    assert_match(/Pre Test/, response.body)
  end

  test "ref 비어있으면 400" do
    get preview_by_ref_orders_path, params: { ref: "" }
    assert_response :bad_request
  end

  test "캐시 hit — 두 번째 요청도 200 + 동일 응답" do
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    first_body = response.body
    get preview_by_ref_orders_path, params: { ref: "PBR-2026-0001" }
    assert_response :success
    assert_equal first_body, response.body
  end

  test "존재하지 않는 ref → 데이터 없음" do
    get preview_by_ref_orders_path, params: { ref: "NONEXIST-9999" }
    assert_response :success
    # 로그인 사용자의 로케일은 User#preferred_locale = `locale.presence || "en"` 을 따른다.
    # 테스트 사용자는 locale 미지정이라 영어("No data")가 렌더된다 — 앱 동작이 정상이고
    # 한국어 문구를 하드코딩한 테스트가 잘못이었다.
    # i18n 키로 검증해 로케일이 바뀌어도 깨지지 않게 한다.
    assert_match(/#{Regexp.escape(I18n.t("orders.refno_preview.no_data", locale: :en))}/, response.body)
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
