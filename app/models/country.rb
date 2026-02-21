# frozen_string_literal: true

class Country < ApplicationRecord
  has_many :companies, dependent: :destroy

  REGIONS = ["Middle East", "Asia", "Pacific", "Europe", "Americas", "Africa"].freeze

  validates :code, :name, :name_en, presence: true
  validates :code, uniqueness: true, length: { is: 2 }

  scope :by_sort,   -> { order(:sort_order, :name) }
  scope :with_tree, -> { includes(companies: { departments: :employees }) }

  def employee_count
    Employee.joins(department: :company).where(companies: { country_id: id }).count
  end
end
