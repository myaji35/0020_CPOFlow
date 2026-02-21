# frozen_string_literal: true

class Company < ApplicationRecord
  belongs_to :country
  has_many :departments, dependent: :destroy
  has_many :employees, through: :departments
  has_many :users

  COMPANY_TYPES = {
    "hq"          => "본사",
    "branch"      => "지사",
    "site_office" => "현장법인"
  }.freeze

  validates :name, :company_type, presence: true
  validates :company_type, inclusion: { in: COMPANY_TYPES.keys }

  scope :active,  -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  def company_type_label = COMPANY_TYPES[company_type] || company_type
  def employee_count     = employees.count
end
