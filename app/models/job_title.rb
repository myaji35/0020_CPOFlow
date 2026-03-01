# frozen_string_literal: true

class JobTitle < ApplicationRecord
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  scope :active,  -> { where(active: true) }
  scope :by_sort, -> { order(:sort_order, :name) }

  def employee_count
    Employee.where(job_title: name).count
  end
end
