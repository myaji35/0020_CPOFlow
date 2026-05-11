# ISS-303: HR 모델 변경 이력을 Activity polymorphic으로 자동 기록.
# 사용: include Auditable + audit_fields :name, :email, ... (Order의 ISS-203 패턴과 동일)
#
# 컨트롤러에서 Current.user = current_user 가 set되어 있어야 user 추적이 정확함
# (ApplicationController가 before_action :set_current_user로 처리).
module Auditable
  extend ActiveSupport::Concern

  class_methods do
    def audit_fields(*fields)
      @audit_fields = fields.map(&:to_s).freeze
    end

    def audited_field_names
      @audit_fields || []
    end
  end

  included do
    after_create  :audit_created
    after_update  :audit_field_changes
    after_destroy :audit_destroyed
  end

  private

  def audit_created
    return unless Current.user
    Activity.create!(
      auditable: self,
      user:      Current.user,
      action:    "created"
    )
  rescue => e
    Rails.logger.warn "[Auditable] create log 실패 #{self.class.name}##{id}: #{e.message}"
  end

  def audit_field_changes
    return unless Current.user
    self.class.audited_field_names.each do |field|
      change = saved_change_to_attribute(field)
      next unless change
      old_val, new_val = change
      next if old_val.to_s == new_val.to_s
      Activity.create!(
        auditable: self,
        user:      Current.user,
        action:    "field_changed",
        field:     field,
        old_value: old_val.to_s,
        new_value: new_val.to_s
      )
    end
  rescue => e
    Rails.logger.warn "[Auditable] update log 실패 #{self.class.name}##{id}: #{e.message}"
  end

  def audit_destroyed
    return unless Current.user
    Activity.create!(
      auditable_type: self.class.name,
      auditable_id:   id,
      user:           Current.user,
      action:         "destroyed"
    )
  rescue => e
    Rails.logger.warn "[Auditable] destroy log 실패 #{self.class.name}##{id}: #{e.message}"
  end
end
