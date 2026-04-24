# frozen_string_literal: true

# ISS-269: Order 동시 편집 충돌 방지 — ActiveRecord optimistic locking 도입
#
# 두 사용자가 같은 오더를 동시에 로드한 후 각자 저장하면 나중 저장이
# 먼저 저장을 덮어써서 데이터 유실 (last-write-wins).
# lock_version 컬럼이 있으면 Rails가 UPDATE WHERE lock_version=? 절을
# 자동 추가하여 stale update를 ActiveRecord::StaleObjectError로 차단.
#
# 기존 데이터: default 0, null: false → 전 Row에 0 설정 후 stable.
# 추가 이후 app/models/order.rb 에서는 특별한 선언 불필요 (Rails convention).
class AddLockVersionToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :lock_version, :integer, default: 0, null: false
  end
end
