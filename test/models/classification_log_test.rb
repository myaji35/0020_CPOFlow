# frozen_string_literal: true

require "test_helper"

class ClassificationLogTest < ActiveSupport::TestCase
  def teardown
    ClassificationLog.where(classifier_version: "v2_test").destroy_all
  end

  test "validates — classifier_version 필수" do
    log = ClassificationLog.new(classifier_version: "")
    assert_not log.valid?
    assert log.errors[:classifier_version].present?
  end

  test "create — 유효한 분류 로그 생성" do
    log = ClassificationLog.create!(classifier_version: "v2_test", would_exclude: false)
    assert log.persisted?
  end

  test "scope v2 — classifier_version v2만 반환" do
    result = ClassificationLog.v2
    assert result.is_a?(ActiveRecord::Relation)
    result.each { |l| assert_equal "v2", l.classifier_version }
  end

  test "scope shadow_would_exclude — would_exclude: true만 반환" do
    result = ClassificationLog.shadow_would_exclude
    assert result.is_a?(ActiveRecord::Relation)
    result.each { |l| assert l.would_exclude }
  end

  test "scope since_today — 오늘 이후 생성된 것만" do
    result = ClassificationLog.since_today
    assert result.is_a?(ActiveRecord::Relation)
    result.each { |l| assert l.created_at >= Time.current.beginning_of_day }
  end

  test "belongs_to order optional" do
    log = ClassificationLog.create!(classifier_version: "v2_test", order: nil)
    assert log.persisted?
    assert_nil log.order
  end
end
