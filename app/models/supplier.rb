class Supplier < ApplicationRecord
  has_many :contact_persons,   as: :contactable, dependent: :destroy
  has_many :supplier_products, dependent: :destroy
  has_many :products,          through: :supplier_products
  has_many :orders,            dependent: :nullify

  CREDIT_GRADES = %w[A B C D].freeze
  PAYMENT_TERMS = %w[NET30 NET60 NET90 COD Advance].freeze

  validates :name, presence: true

  scope :active,  -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  def primary_contact    = contact_persons.find_by(primary: true) || contact_persons.first
  def total_supply_value = orders.sum(:estimated_value).to_f
  def industry_label
    { "nuclear" => "원전", "hydro" => "수력", "tunnel" => "터널",
      "gtx" => "GTX", "construction" => "건설", "general" => "일반" }[industry] || industry
  end

  # ISS-204: eCount snapshot과 현재 DB 값의 차이 반환
  # 반환: [{field:, ecount:, local:, label:}, ...] — diff 없으면 빈 배열
  def ecount_diff
    return [] if ecount_snapshot.blank?
    snap = ecount_snapshot.is_a?(String) ? (JSON.parse(ecount_snapshot) rescue {}) : ecount_snapshot
    labels = { "name" => "이름", "country" => "국가", "contact_email" => "이메일",
               "contact_phone" => "전화번호", "notes" => "메모" }
    diffs = []
    %w[name country contact_email contact_phone notes].each do |field|
      local_val = self[field].to_s.strip
      ecount_val = snap[field].to_s.strip
      next if local_val == ecount_val
      diffs << { field: field, label: labels[field] || field, local: local_val, ecount: ecount_val }
    end
    diffs
  end
end
