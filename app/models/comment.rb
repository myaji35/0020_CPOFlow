class Comment < ApplicationRecord
  belongs_to :order
  belongs_to :user

  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
end
