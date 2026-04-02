require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "User role enum 유효" do
    %w[viewer member manager admin].each do |r|
      assert User.roles.key?(r), "role #{r} 누락"
    end
  end

  test "User branch enum 유효" do
    %w[abu_dhabi seoul].each do |b|
      assert User.branches.key?(b), "branch #{b} 누락"
    end
  end

  test "User associations 쿼리 정상" do
    assert_nothing_raised do
      User.includes(:created_orders, :assigned_orders, :notifications).limit(5).to_a
    end
  end

  test "User scopes 정상 동작" do
    assert_nothing_raised { User.all.count }
  end
end
