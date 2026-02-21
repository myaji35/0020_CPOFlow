class Assignment < ApplicationRecord
  belongs_to :user
  belongs_to :order

  validates :user_id, uniqueness: { scope: :order_id }
end
