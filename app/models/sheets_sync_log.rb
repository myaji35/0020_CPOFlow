# frozen_string_literal: true

class SheetsSyncLog < ApplicationRecord
  STATUSES = %w[pending success failed mock].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc).limit(10) }

  def success? = status == "success"
  def failed?  = status == "failed"
  def mock?    = status == "mock"
  def pending? = status == "pending"

  def total_count
    orders_count.to_i + projects_count.to_i + employees_count.to_i + visas_count.to_i
  end

  def status_label
    case status
    when "success" then "성공"
    when "failed"  then "실패"
    when "mock"    then "Mock 완료"
    when "pending" then "진행중"
    end
  end

  def status_color
    case status
    when "success" then "green"
    when "failed"  then "red"
    when "mock"    then "blue"
    when "pending" then "yellow"
    end
  end
end
