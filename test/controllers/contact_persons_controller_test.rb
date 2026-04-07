# frozen_string_literal: true

require "test_helper"

class ContactPersonsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.find_or_create_by(email: "contact_persons_ctrl_test@example.com") do |u|
      u.name = "Contact Persons Test"; u.password = "password123"; u.role = :manager
    end
    @user.update!(role: :manager)
    login_as(@user)
    @client = Client.create!(name: "CP Test Client", code: "CLI-CP-#{SecureRandom.hex(4)}", country: "KR")
    @contact_person = ContactPerson.create!(
      name: "Test Contact Kim",
      contactable: @client
    )
  end

  def teardown
    @contact_person.destroy if ContactPerson.exists?(@contact_person.id)
    @client.destroy if Client.exists?(@client.id)
  end

  test "contact_persons index 200" do
    get contact_persons_path
    assert_response :success
  end

  test "contact_persons index — 담당자 이름 표시" do
    get contact_persons_path
    assert_match "Test Contact Kim", response.body
  end

  test "contact_persons show 200" do
    get contact_person_path(@contact_person)
    assert_response :success
  end

  test "contact_persons new form — client context" do
    get new_client_contact_person_path(@client)
    assert_response :success
  end

  test "contact_persons create — 성공" do
    assert_difference("ContactPerson.count", 1) do
      post client_contact_persons_path(@client), params: {
        contact_person: { name: "New Contact Lee" }
      }
    end
    ContactPerson.find_by(name: "New Contact Lee")&.destroy
  end

  test "contact_persons create — name 없으면 실패" do
    assert_no_difference("ContactPerson.count") do
      post client_contact_persons_path(@client), params: {
        contact_person: { name: "" }
      }
    end
  end

  test "contact_persons update — name 변경" do
    patch client_contact_person_path(@client, @contact_person), params: {
      contact_person: { name: "Updated Contact" }
    }
    @contact_person.reload
    assert_equal "Updated Contact", @contact_person.name
  end

  test "contact_persons destroy — 삭제" do
    cp = ContactPerson.create!(name: "Delete Me Contact", contactable: @client)
    assert_difference("ContactPerson.count", -1) do
      delete client_contact_person_path(@client, cp)
    end
  end

  private

  def login_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end
end
