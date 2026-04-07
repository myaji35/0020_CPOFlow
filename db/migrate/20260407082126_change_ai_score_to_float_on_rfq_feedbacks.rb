# frozen_string_literal: true

# ai_score 컬럼을 float 로 변경
# - 기존: integer (0~100 가정, 사용 이력 없음)
# - 변경: float (0.0 ~ 1.0 confidence score 저장)
# - Phase E: 학습 통계 평균 계산용
class ChangeAiScoreToFloatOnRfqFeedbacks < ActiveRecord::Migration[8.1]
  def up
    change_column :rfq_feedbacks, :ai_score, :float
  end

  def down
    change_column :rfq_feedbacks, :ai_score, :integer
  end
end
