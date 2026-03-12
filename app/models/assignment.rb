class Assignment < ApplicationRecord
  belongs_to :employee, optional: true
  belongs_to :user, optional: true
  belongs_to :order

  validates :employee_id, uniqueness: { scope: :order_id }
end
