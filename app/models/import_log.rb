# frozen_string_literal: true

class ImportLog < ApplicationRecord
  belongs_to :user
  has_one_attached :import_file

  enum :status,      { pending: 0, processing: 1, completed: 2, failed: 3 }, default: :pending
  enum :import_type, { products: "products", suppliers: "suppliers", orders: "orders" },
       default: :products

  validates :import_type, presence: true
  validates :filename,    presence: true

  def error_rows_array
    JSON.parse(error_details || "[]")
  end

  def preview_rows
    JSON.parse(preview_data || "[]")
  end

  def progress_percent
    return 0 if total_rows.to_i.zero?
    ((success_rows.to_i + error_rows.to_i) * 100.0 / total_rows).round
  end

  def import_type_label
    case import_type
    when "products"  then "품목"
    when "suppliers" then "거래처"
    when "orders"    then "거래이력"
    end
  end

  def status_label
    case status
    when "pending"    then "대기 중"
    when "processing" then "처리 중"
    when "completed"  then "완료"
    when "failed"     then "실패"
    end
  end
end
