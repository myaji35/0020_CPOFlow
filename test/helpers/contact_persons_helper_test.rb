# frozen_string_literal: true

require "test_helper"

class ContactPersonsHelperTest < ActionView::TestCase
  include ContactPersonsHelper

  def setup
    @client   = Client.create!(name: "Test Client Hlpr", code: "CLHLP#{rand(9999)}")
    @supplier = Supplier.create!(name: "Test Supplier Hlpr", code: "SPHLP#{rand(9999)}")
    @cp = ContactPerson.create!(name: "홍길동", email: "hong@example.com",
                                contactable: @client)
  end

  def teardown
    @cp.destroy
    @client.destroy
    @supplier.destroy
  end

  test "contactable_type_label — Client → 발주처" do
    assert_equal "발주처", contactable_type_label(@client)
  end

  test "contactable_type_label — Supplier → 거래처" do
    assert_equal "거래처", contactable_type_label(@supplier)
  end

  test "contactable_badge_class — Client returns blue class" do
    result = contactable_badge_class(@client)
    assert_includes result, "blue"
  end

  test "contactable_badge_class — Supplier returns purple class" do
    result = contactable_badge_class(@supplier)
    assert_includes result, "purple"
  end

  test "edit_contactable_contact_person_path — Client path" do
    path = edit_contactable_contact_person_path(@client, @cp)
    assert_includes path, "/clients/"
  end

  test "edit_contactable_contact_person_path — Supplier path" do
    cp_s = ContactPerson.create!(name: "김공급", email: "kim@example.com", contactable: @supplier)
    path = edit_contactable_contact_person_path(@supplier, cp_s)
    assert_includes path, "/suppliers/"
    cp_s.destroy
  end

  test "contactable_contact_person_path — Client path" do
    path = contactable_contact_person_path(@client, @cp)
    assert_includes path, "/clients/"
  end

  test "contactable_contact_person_path — Supplier path" do
    cp_s = ContactPerson.create!(name: "박거래", email: "park@example.com", contactable: @supplier)
    path = contactable_contact_person_path(@supplier, cp_s)
    assert_includes path, "/suppliers/"
    cp_s.destroy
  end
end
