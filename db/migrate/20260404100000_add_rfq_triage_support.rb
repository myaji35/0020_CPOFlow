# frozen_string_literal: true

# rfq_status enum 변경:
#   rfq_confirmed(0) → rfq_triage(0)    이름만 변경, DB값 유지
#   rfq_uncertain(1) → rfq_pending(1)   이름만 변경, DB값 유지
#   rfq_excluded(2)  → rfq_excluded(2)  변경 없음
#   신규: rfq_archived(3)               칸반 이동 후 상태
#
# 기존 데이터 마이그레이션:
#   - rfq_confirmed(0) 중 칸반 진입 완료(status != new_rfq) → rfq_archived(3)
#   - rfq_confirmed(0) 중 아직 inbox(status == new_rfq) → rfq_triage(0) 유지
#   - rfq_uncertain(1) → rfq_pending(1) DB값 동일, 변경 불필요
class AddRfqTriageSupport < ActiveRecord::Migration[8.0]
  def up
    # 1. rfq_feedbacks에 ai_score 컬럼 추가 (정답 데이터 기록용)
    add_column :rfq_feedbacks, :ai_score, :integer, default: nil

    # 2. 기존 rfq_confirmed(0) 중 칸반 진입 완료건 → rfq_archived(3)
    execute <<~SQL
      UPDATE orders
      SET rfq_status = 3
      WHERE rfq_status = 0
        AND status != 0
    SQL

    # 3. 기존 new_rfq + rfq_uncertain(1) → rfq_pending(1) — DB값 동일, 변경 불필요
    # 4. 기존 new_rfq + rfq_confirmed(0) → rfq_triage(0) — DB값 동일, 유지
  end

  def down
    # rfq_archived(3) → rfq_confirmed(0) 복원
    execute <<~SQL
      UPDATE orders
      SET rfq_status = 0
      WHERE rfq_status = 3
    SQL

    remove_column :rfq_feedbacks, :ai_score
  end
end
