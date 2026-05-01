class Task < ApplicationRecord
  belongs_to :order
  belongs_to :assignee, class_name: "User", optional: true

  # ISS-293: RFP 자동 분석으로 생성된 태스크 메타데이터
  # source_attachment_id: 원본 첨부 blob id (ActiveStorage::Blob id)
  # source_excerpt: LLM이 인용한 원문 (할루시네이션 방지)
  # feedback_score: +1 (좋음) / -1 (나쁨) / nil (미평가)
  # auto_generated: LLM 자동 생성 여부

  validates :title, presence: true, length: { maximum: 255 }
  validates :order, presence: true
  validates :feedback_score, inclusion: { in: [ 1, -1, nil ] }, allow_nil: true

  scope :pending, -> { where(completed: false) }
  scope :done, -> { where(completed: true) }
  scope :by_due, -> { order(due_date: :asc, created_at: :asc) }
  scope :auto_generated, -> { where(auto_generated: true) }
  scope :manual, -> { where(auto_generated: false) }

  def overdue?
    !completed && due_date.present? && due_date < Date.today
  end
end
