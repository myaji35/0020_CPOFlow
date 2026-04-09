# frozen_string_literal: true

# v2 이메일 분류 파이프라인(Gmail::ClassificationOrchestrator)의
# stage별 판정 결과를 기록. Shadow Mode 기간 동안 v2가 excluded로
# 판정한 건도 Order.rfq_status는 rfq_pending으로 저장되며, 이 테이블의
# would_exclude=true 플래그로 추적된다. Phase C4(ISS-054) ShadowFnDetectorJob이
# 이 플래그를 사용해 False Negative를 감지한다.
class ClassificationLog < ApplicationRecord
  belongs_to :order, optional: true

  validates :classifier_version, presence: true

  scope :v2,            -> { where(classifier_version: "v2") }
  scope :shadow_would_exclude, -> { where(would_exclude: true) }
  scope :since_today,   -> { where("created_at >= ?", Time.current.beginning_of_day) }
end
