# frozen_string_literal: true

require "test_helper"

class EmailAccountTest < ActiveSupport::TestCase
  def setup
    @user = User.find_or_create_by(email: "email_account_model_test@example.com") do |u|
      u.name = "Email Account Model Test"; u.password = "password123"; u.role = :member
    end
  end

  def teardown
    EmailAccount.where(user: @user).destroy_all
  end

  test "create — 유효한 이메일 계정 생성" do
    acct = @user.email_accounts.create!(email: "test_ea_model@example.com")
    assert acct.persisted?
  end

  test "belongs_to user" do
    acct = @user.email_accounts.create!(email: "ea_belongs_test@example.com")
    assert_equal @user, acct.user
  end

  test "validates — email 필수" do
    acct = @user.email_accounts.build(email: "")
    assert_not acct.valid?
  end
end
