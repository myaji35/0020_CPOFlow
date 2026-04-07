require "test_helper"

class ContactPersonTest < ActiveSupport::TestCase
  # validates
  test "name 없으면 invalid" do
    cp = ContactPerson.new(contactable_type: "Client", contactable_id: 1)
    assert_not cp.valid?
    assert cp.errors[:name].any?
  end

  test "유효하지 않은 email 형식이면 invalid" do
    cp = ContactPerson.new(name: "Test", email: "not-an-email",
                           contactable_type: "Client", contactable_id: 1)
    assert_not cp.valid?
  end

  test "빈 email은 허용됨" do
    cp = ContactPerson.new(name: "Test", email: "",
                           contactable_type: "Client", contactable_id: 1)
    # email blank → allow_blank: true
    cp.valid?
    assert cp.errors[:email].empty?
  end

  test "유효하지 않은 source는 invalid" do
    cp = ContactPerson.new(name: "Test", source: "unknown",
                           contactable_type: "Client", contactable_id: 1)
    assert_not cp.valid?
  end

  test "유효한 source는 valid" do
    cp = ContactPerson.new(name: "Test", source: "manual",
                           contactable_type: "Client", contactable_id: 1)
    cp.valid?
    assert cp.errors[:source].empty?
  end

  # language_label
  test "language_label: en이면 English" do
    cp = ContactPerson.new(name: "Test", language: "en",
                           contactable_type: "Client", contactable_id: 1)
    assert_equal "English", cp.language_label
  end

  test "language_label: 미지원 코드면 코드 그대로" do
    cp = ContactPerson.new(name: "Test", language: "zz",
                           contactable_type: "Client", contactable_id: 1)
    assert_equal "zz", cp.language_label
  end

  # display_name
  test "display_name: primary이면 이름 뒤에 ★" do
    cp = ContactPerson.new(name: "Alice", primary: true,
                           contactable_type: "Client", contactable_id: 1)
    assert_equal "Alice ★", cp.display_name
  end

  test "display_name: primary 아니면 이름만" do
    cp = ContactPerson.new(name: "Bob", primary: false,
                           contactable_type: "Client", contactable_id: 1)
    assert_equal "Bob", cp.display_name
  end

  # contactable_label
  test "contactable_label: Client이면 발주처" do
    cp = ContactPerson.new(name: "Test", contactable_type: "Client", contactable_id: 1)
    assert_equal "발주처", cp.contactable_label
  end

  test "contactable_label: Supplier이면 거래처" do
    cp = ContactPerson.new(name: "Test", contactable_type: "Supplier", contactable_id: 1)
    assert_equal "거래처", cp.contactable_label
  end

  # last_contacted_label
  test "last_contacted_label: nil이면 '-'" do
    cp = ContactPerson.new(name: "Test", contactable_type: "Client", contactable_id: 1,
                           last_contacted_at: nil)
    assert_equal "-", cp.last_contacted_label
  end

  test "last_contacted_label: 오늘이면 '오늘'" do
    cp = ContactPerson.new(name: "Test", contactable_type: "Client", contactable_id: 1,
                           last_contacted_at: Time.current)
    assert_equal "오늘", cp.last_contacted_label
  end

  test "last_contacted_label: 어제이면 '어제'" do
    cp = ContactPerson.new(name: "Test", contactable_type: "Client", contactable_id: 1,
                           last_contacted_at: 1.day.ago)
    assert_equal "어제", cp.last_contacted_label
  end

  test "last_contacted_label: 31일 이상이면 날짜 형식" do
    cp = ContactPerson.new(name: "Test", contactable_type: "Client", contactable_id: 1,
                           last_contacted_at: 40.days.ago)
    assert_match(/\d{4}-\d{2}-\d{2}/, cp.last_contacted_label)
  end

  # scopes
  test "primary_first scope 동작" do
    assert_nothing_raised { ContactPerson.primary_first.count }
  end

  test "for_clients scope 동작" do
    assert_nothing_raised { ContactPerson.for_clients.count }
  end

  test "for_suppliers scope 동작" do
    assert_nothing_raised { ContactPerson.for_suppliers.count }
  end

  test "search scope: 빈 문자열이면 전체 반환" do
    assert_nothing_raised { ContactPerson.search("").count }
  end

  test "search scope: 검색어 있으면 필터링" do
    assert_nothing_raised { ContactPerson.search("alice").count }
  end

  # 상수
  test "LANGUAGES 상수 존재" do
    assert ContactPerson::LANGUAGES.key?("en")
    assert ContactPerson::LANGUAGES.key?("ko")
  end

  test "DEPARTMENTS 상수 존재" do
    assert ContactPerson::DEPARTMENTS.include?("Sales")
  end

  test "SOURCES 상수 존재" do
    assert ContactPerson::SOURCES.include?("manual")
    assert ContactPerson::SOURCES.include?("email_signature")
  end
end
