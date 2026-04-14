# frozen_string_literal: true

require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  def setup
    AppSetting.find_by(key: "test_setting_key_#{self.class}")&.destroy
  end

  def teardown
    AppSetting.where("key LIKE 'test_setting%'").destroy_all
  end

  test "set/get — 값 저장 후 조회" do
    AppSetting.set("test_setting_key_1", "test_value_1")
    assert_equal "test_value_1", AppSetting.get("test_setting_key_1")
  end

  test "get — 없는 키는 nil 반환" do
    assert_nil AppSetting.get("nonexistent_key_xyz_#{SecureRandom.hex(4)}")
  end

  test "set — 같은 키로 덮어쓰기" do
    AppSetting.set("test_setting_update", "first_value")
    AppSetting.set("test_setting_update", "second_value")
    assert_equal "second_value", AppSetting.get("test_setting_update")
  end

  test "validates — key 없으면 유효하지 않음" do
    setting = AppSetting.new(key: "", value: "val")
    assert_not setting.valid?
  end

  test "validates — key 중복 불가" do
    AppSetting.set("test_setting_dup", "val1")
    duplicate = AppSetting.new(key: "test_setting_dup", value: "val2")
    assert_not duplicate.valid?
  end

  test "google_chat_webhook_url — AppSetting에서 읽기" do
    AppSetting.set("google_chat_webhook_url", "https://hooks.example.com/webhook")
    assert_equal "https://hooks.example.com/webhook", AppSetting.google_chat_webhook_url
    AppSetting.find_by(key: "google_chat_webhook_url")&.destroy
  end
end
