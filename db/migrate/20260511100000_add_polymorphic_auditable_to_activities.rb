# ISS-303: HR 변경이력 감사 로그 시스템.
# 기존 Activity는 Order 전용(order_id null:false)이었는데, Employee/Visa/EmploymentContract/Certification까지
# 같은 모델로 추적할 수 있도록 polymorphic auditable_type/auditable_id 추가.
# - order_id는 backwards compat 위해 유지 (HR 외 기존 사용처 보존, 추후 데이터 마이그레이션은 별도 이슈)
# - auditable이 채워진 row는 polymorphic 경로, 비어있는 row는 기존 order_id 경로.
class AddPolymorphicAuditableToActivities < ActiveRecord::Migration[8.1]
  def change
    add_reference :activities, :auditable, polymorphic: true, null: true, index: true

    # order_id를 nullable로 완화: HR 감사 로그는 order_id가 비어있다.
    change_column_null :activities, :order_id, true
  end
end
