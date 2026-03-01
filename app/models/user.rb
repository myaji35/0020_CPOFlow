class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email    = auth.info.email
      user.name     = auth.info.name
      user.password = Devise.friendly_token[0, 20]
      user.provider = auth.provider
      user.uid      = auth.uid
      # 비밀번호 검증 스킵 (OmniAuth 유저)
      user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
    end
  end

  enum :role, { viewer: 0, member: 1, manager: 2, admin: 3 }, default: :member
  enum :branch, { abu_dhabi: "abu_dhabi", seoul: "seoul" }, default: :abu_dhabi

  LOCALES = %w[en ko ar].freeze
  THEMES  = %w[light dark system].freeze

  belongs_to :company, optional: true

  has_many :email_accounts, dependent: :destroy
  has_many :created_orders, class_name: "Order", foreign_key: :user_id, dependent: :nullify
  has_many :assignments, dependent: :destroy
  has_many :assigned_orders, through: :assignments, source: :order
  has_many :tasks, foreign_key: :assignee_id, dependent: :nullify
  has_many :comments, dependent: :nullify
  has_many :activities, dependent: :nullify
  has_many :notifications, dependent: :destroy
  has_one  :employee, dependent: :nullify

  validates :name, presence: true
  validates :locale, inclusion: { in: LOCALES }, allow_blank: true
  validates :theme,  inclusion: { in: THEMES },  allow_blank: true

  # Employee 연결 시 직원 이름 우선 표시, 없으면 User.name
  def display_name
    employee&.name.presence || name.presence || email.split("@").first
  end

  def initials
    display_name.split.map(&:first).first(2).join.upcase
  end

  def linked_to_employee?
    employee.present?
  end

  def admin_or_manager?
    admin? || manager?
  end

  def preferred_locale
    locale.presence || "en"
  end

  def preferred_theme
    theme.presence || "light"
  end

  def dark_mode?
    preferred_theme == "dark"
  end
end
