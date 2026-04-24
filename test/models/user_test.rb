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

  # ISS-268: 이메일 도메인 기반 branch 추정
  test "infer_branch_from_email — seoul 추정 (.kr, korea, seoul 키워드)" do
    assert_equal :seoul, User.infer_branch_from_email("alice@atozone.kr")
    assert_equal :seoul, User.infer_branch_from_email("bob@seoul-branch.com")
    assert_equal :seoul, User.infer_branch_from_email("charlie@korea.atozone.com")
  end

  test "infer_branch_from_email — abu_dhabi 추정 (.ae, abudhabi, uae)" do
    assert_equal :abu_dhabi, User.infer_branch_from_email("alice@atozone.ae")
    assert_equal :abu_dhabi, User.infer_branch_from_email("bob@abudhabi.atozone.com")
    assert_equal :abu_dhabi, User.infer_branch_from_email("charlie@uae-mail.com")
  end

  test "infer_branch_from_email — 모호한 도메인은 nil (default 유지)" do
    assert_nil User.infer_branch_from_email("alice@gmail.com")
    assert_nil User.infer_branch_from_email("")
    assert_nil User.infer_branch_from_email(nil)
  end
end
