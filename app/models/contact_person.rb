class ContactPerson < ApplicationRecord
  self.table_name = "contact_persons"

  belongs_to :contactable, polymorphic: true

  LANGUAGES = { "en" => "English", "ko" => "한국어", "ar" => "العربية",
                "zh" => "中文", "ja" => "日本語" }.freeze

  DEPARTMENTS = %w[Sales Technical CS Procurement Management Finance Other].freeze

  SOURCES = %w[manual email_signature import].freeze

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :source,     inclusion: { in: SOURCES }, allow_blank: true
  validates :department, inclusion: { in: DEPARTMENTS }, allow_blank: true

  scope :primary_first,      -> { order(primary: :desc, name: :asc) }
  scope :with_contactable,   -> { includes(:contactable) }
  scope :recently_contacted, -> { order(last_contacted_at: :desc, name: :asc) }
  scope :for_clients,        -> { where(contactable_type: "Client") }
  scope :for_suppliers,      -> { where(contactable_type: "Supplier") }
  scope :primary_only,       -> { where(primary: true) }
  scope :by_department,      ->(dept) { dept.present? ? where(department: dept) : all }

  scope :search, ->(q) {
    return all if q.blank?
    term = "%#{q.downcase}%"
    where(
      "LOWER(contact_persons.name) LIKE ? OR LOWER(contact_persons.email) LIKE ? " \
      "OR contact_persons.phone LIKE ? OR contact_persons.mobile LIKE ?",
      term, term, term, term
    )
  }

  def language_label     = LANGUAGES[language] || language
  def display_name       = primary? ? "#{name} ★" : name
  def contactable_name   = contactable&.name
  def contactable_label  = contactable_type == "Client" ? "발주처" : "거래처"

  def last_contacted_label
    return "-" if last_contacted_at.nil?
    days = ((Time.current - last_contacted_at) / 1.day).round
    case days
    when 0      then "오늘"
    when 1      then "어제"
    when 2..30  then "#{days}일 전"
    else        last_contacted_at.strftime("%Y-%m-%d")
    end
  end
end
