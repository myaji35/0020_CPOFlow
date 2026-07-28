require "test_helper"

# ISS-387 (ISS-342 E2): Rfp::ClientMatcher 단위 테스트
# 이 프로젝트는 fixture를 쓰지 않는다 (test_helper.rb 참고) — 레코드 직접 생성.
# ClientMatcher는 order의 sender_domain / original_email_from / id 만 읽으므로
# Order는 저장하지 않는다 (필수 belongs_to :user 와 after_create_commit 콜백 회피).
class Rfp::ClientMatcherTest < ActiveSupport::TestCase
  def build_order(sender_domain:, original_email_from: nil)
    Order.new(sender_domain: sender_domain, original_email_from: original_email_from)
  end

  def uniq_code
    "TST-#{SecureRandom.hex(4)}"
  end

  test "자사 도메인 발신은 skip 된다" do
    result = Rfp::ClientMatcher.call(build_order(sender_domain: "atoz2010.com"))

    assert_equal "skipped", result[:source]
    assert_nil result[:client]
  end

  test "ariba relay 단독 발신은 skip 된다" do
    order = build_order(
      sender_domain: "ariba.com",
      original_email_from: "Ariba Network <noreply@ariba.com>"
    )
    result = Rfp::ClientMatcher.call(order)

    assert_equal "skipped", result[:source]
    assert_nil result[:client]
  end

  test "DOMAIN_ALIASES 에 등록된 도메인은 alias 로 매칭된다" do
    Client.create!(name: "ENEC Barakah Test", code: uniq_code, country: "AE")

    result = Rfp::ClientMatcher.call(build_order(sender_domain: "nawah.ae"))

    assert result[:source].start_with?("domain_alias"), "source=#{result[:source]}"
    assert_equal 0.95, result[:confidence]
    # find_client_by_alias 는 LIKE "%enec%" 의 first 를 반환하므로
    # 특정 레코드가 아니라 "enec 를 담은 Client 가 매칭되었다" 를 검증한다.
    assert_not_nil result[:client]
    assert_match(/enec/i, "#{result[:client].name}#{result[:client].website}")
  end

  # NOTE: ISS-399 부터 normalize_domain 이 URL 스킴/www./경로/포트를 제거한다.
  #       website 가 스킴 포함 URL 로 저장돼 있어도 매칭된다 (아래 스킴 케이스 테스트 참고).
  test "website 가 정확히 일치하면 website_match 로 매칭된다" do
    client = Client.create!(
      name: "UniqueCorp Test",
      code: uniq_code,
      country: "AE",
      website: "uniquecorp-test.example.com"
    )

    result = Rfp::ClientMatcher.call(build_order(sender_domain: "uniquecorp-test.example.com"))

    assert_equal "website_match", result[:source]
    assert_equal 0.90, result[:confidence]
    assert_equal client, result[:client]
  end

  # 실패경로 4문항 #1: 미매칭 시 가짜 client 를 만들어내지 않아야 한다.
  test "미등록 도메인은 no_match 이며 client 를 지어내지 않는다" do
    result = Rfp::ClientMatcher.call(build_order(sender_domain: "totally-unknown-xyz-9182.com"))

    assert_equal "no_match", result[:source]
    assert_nil result[:client]
    assert_equal 0.0, result[:confidence]
  end

  test "'Name <addr@DOMAIN>' 형태의 sender_domain 도 정규화되어 매칭된다" do
    client = Client.create!(
      name: "UniqueCorp Test",
      code: uniq_code,
      country: "AE",
      website: "uniquecorp-test.example.com"
    )

    order = build_order(sender_domain: "Some Name <buyer@UNIQUECORP-TEST.EXAMPLE.COM>")
    result = Rfp::ClientMatcher.call(order)

    assert_equal "website_match", result[:source]
    assert_equal client, result[:client]
  end

  # ISS-399: website 가 스킴 포함 URL 로 저장돼 있어도 매칭되어야 한다.
  test "website 에 https:// 스킴이 있어도 website_match 로 매칭된다" do
    client = Client.create!(
      name: "SchemeTest Corp",
      code: uniq_code,
      country: "AE",
      website: "https://schemetest-xyz.example.com"
    )

    result = Rfp::ClientMatcher.call(build_order(sender_domain: "schemetest-xyz.example.com"))

    assert_equal "website_match", result[:source]
    assert_equal client, result[:client]
  end

  test "website 에 www. 와 경로/쿼리가 있어도 website_match 로 매칭된다" do
    client = Client.create!(
      name: "PathTest Corp",
      code: uniq_code,
      country: "AE",
      website: "https://www.pathtest-xyz.example.com/about?a=1"
    )

    result = Rfp::ClientMatcher.call(build_order(sender_domain: "pathtest-xyz.example.com"))

    assert_equal "website_match", result[:source]
    assert_equal client, result[:client]
  end
end
