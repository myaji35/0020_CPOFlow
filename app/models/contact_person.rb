class ContactPerson < ApplicationRecord
  self.table_name = "contact_persons"

  belongs_to :contactable, polymorphic: true

  LANGUAGES = { "en" => "English", "ko" => "한국어", "ar" => "العربية",
                "zh" => "中文", "ja" => "日本語" }.freeze

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :primary_first, -> { order(primary: :desc, name: :asc) }

  def language_label = LANGUAGES[language] || language
  def display_name   = primary? ? "#{name} ★" : name
end
