Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
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
    member do
      patch :move_status
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

  # 거래처 (Suppliers)
  resources :suppliers do
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

  # Settings
  namespace :settings do
    get "/", to: "base#index", as: :root
    resources :email_accounts, only: %i[index new create destroy]
    patch "profile", to: "profile#update"
    patch "locale", to: "profile#update_locale", as: :update_locale
    get  "menu_permissions",    to: "menu_permissions#index",     as: :menu_permissions
    patch "menu_permissions",   to: "menu_permissions#update_all", as: :update_menu_permissions
  end
end
