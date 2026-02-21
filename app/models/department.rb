# frozen_string_literal: true

class Department < ApplicationRecord
  belongs_to :company
  belongs_to :parent, class_name: "Department", optional: true
  has_many :sub_departments, class_name: "Department", foreign_key: :parent_id, dependent: :nullify
  has_many :employees, foreign_key: :department_id, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :company_id }

  scope :active,     -> { where(active: true) }
  scope :root_level, -> { where(parent_id: nil) }
  scope :by_sort,    -> { order(:sort_order, :name) }

  def full_name      = parent ? "#{parent.name} > #{name}" : name
  def employee_count = employees.active.count
end
