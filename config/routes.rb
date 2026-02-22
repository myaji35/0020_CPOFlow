Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  root to: redirect("/users/sign_in")

  # Dashboard
  get  "dashboard",      to: "dashboard#index"
  post "dashboard/sync", to: "dashboard#sync_sheets", as: :sync_sheets

  # Kanban board
  get "kanban", to: "kanban#index"
  patch "orders/:id/move", to: "kanban#move", as: :move_order

  # Orders (full CRUD + nested resources)
  resources :orders do
    resources :tasks, only: %i[create update destroy]
    resources :comments, only: %i[create destroy]
    resources :assignments, only: %i[create destroy]
    resources :order_quotes, only: %i[new create destroy] do
      member { patch :select }
    end
    member do
      patch :move_status
      get  "pdf/quote",          to: "orders/pdf#quote",           as: :pdf_quote
      get  "pdf/purchase_order", to: "orders/pdf#purchase_order",  as: :pdf_purchase_order
    end
  end

  # Inbox (email view)
  get  "inbox",          to: "inbox#index"
  get  "inbox/:id",      to: "inbox#show",             as: :inbox_email
  post "inbox/:id/convert", to: "inbox#convert_to_order", as: :convert_email_to_order
  post "inbox/sync",     to: "inbox#sync",             as: :inbox_sync

  # Calendar
  get "calendar", to: "calendar#index"

  # Team management
  resources :team, only: %i[index show], controller: "team"

  # Admin namespace
  namespace :admin do
    resources :imports, only: %i[index new create show] do
      member { get :download_errors }
    end
    patch "sheets_config",       to: "sheets_config#update", as: :sheets_config
    delete "sheets_config/clear", to: "sheets_config#clear",  as: :sheets_config_clear
  end

  # Gmail OAuth2
  scope "gmail/oauth" do
    get  "authorize",   to: "gmail_oauth#authorize",   as: :gmail_oauth_authorize
    get  "callback",    to: "gmail_oauth#callback",    as: :gmail_oauth_callback
    delete "disconnect/:id", to: "gmail_oauth#disconnect", as: :gmail_oauth_disconnect
  end

  # 발주처 (Clients)
  resources :clients do
    resources :contact_persons, only: %i[new create edit update destroy]
  end

  # 거래처 (Suppliers) - destroy 제외 (발주 이력 보존)
  resources :suppliers, except: [:destroy] do
    resources :contact_persons, only: %i[new create edit update destroy]
    resources :supplier_products, only: %i[create destroy]
  end

  # 프로젝트 (Projects)
  resources :projects

  # 조직도 (Org Chart)
  get "org_chart", to: "org_chart#index", as: :org_chart

  namespace :org_chart do
    resources :countries, only: %i[index show new create edit update destroy]
    resources :companies, only: %i[index show new create edit update destroy] do
      resources :departments, only: %i[show new create edit update destroy]
    end
  end

  # 직원 관리 (HR System)
  resources :employees do
    resources :visas,                only: %i[new create edit update destroy]
    resources :employment_contracts, only: %i[new create edit update destroy]
    resources :employee_assignments, only: %i[new create edit update destroy]
    resources :certifications,       only: %i[new create edit update destroy]
  end

  # 통합 검색 (Command Palette)
  get "/search", to: "search#index", as: :search

  # 경영 리포트
  get "/reports", to: "reports#index", as: :reports

  # 알림 센터
  resources :notifications, only: %i[index] do
    collection { patch :read_all }
    member     { patch :read }
  end

  # 주문 일괄 처리 (Bulk Actions)
  namespace :orders do
    resource :bulk, only: [] do
      post :update
      get  :export_csv
    end
  end

  # 견적 비교 (Order Quotes)
  resources :orders do
    resources :order_quotes, only: %i[new create destroy] do
      member { patch :select }
    end
  end

  # Settings
  namespace :settings do
    get "/", to: "base#index", as: :root
    resources :email_accounts, only: %i[index new create destroy]
    patch "profile", to: "profile#update"
    patch "locale", to: "profile#update_locale", as: :update_locale
    patch "theme",  to: "profile#update_theme",  as: :update_theme
    get  "menu_permissions",    to: "menu_permissions#index",     as: :menu_permissions
    patch "menu_permissions",   to: "menu_permissions#update_all", as: :update_menu_permissions
  end
end
