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

  # Kanban board (ISS-044: /orders/kanban 직관적 alias redirect)
  get "kanban",         to: "kanban#index"
  get "orders/kanban",  to: redirect("/kanban")
  patch "orders/:id/move", to: "kanban#move", as: :move_order
  post "kanban/merge", to: "kanban#merge", as: :kanban_merge
  patch "kanban/split/:id", to: "kanban#split", as: :kanban_split

  # Orders (full CRUD + nested resources)
  resources :orders do
    collection do
      get :preview_by_ref  # M3-4: 칸반 reference_no 호버 미니프리뷰
    end
    resources :tasks, only: %i[create update destroy]
    resources :comments, only: %i[create destroy]
    resources :assignments, only: %i[create destroy]
    resources :order_quotes, only: %i[new create destroy] do
      member { patch :select }
    end
    resource :flow, only: [ :show ], controller: "order_flows"
    member do
      patch :move_status
      patch :quick_update
      post  :attach
      post  :attach_from_url
      delete "detach/:blob_id", action: :detach, as: :detach
      get  "pdf/quote",          to: "orders/pdf#quote",           as: :pdf_quote
      get  "pdf/purchase_order", to: "orders/pdf#purchase_order",  as: :pdf_purchase_order
      get  "attachment_preview/:blob_id", action: :preview_attachment, as: :attachment_preview
    end
  end

  # Procurement Ontology M3 — OrderLinks
  resources :order_links, only: %i[new create] do
    member do
      patch :confirm
      patch :reject
    end
    collection do
      get :search
    end
  end

  # Inbox (email view)
  get  "inbox",             to: "inbox#index"
  get  "inbox/:id",         to: "inbox#show",               as: :inbox_email
  delete "inbox/:id",       to: "inbox#destroy",            as: :delete_inbox_email
  post "inbox/:id/convert", to: "inbox#convert_to_order",   as: :convert_email_to_order
  post "inbox/sync",        to: "inbox#sync",               as: :inbox_sync
  get  "inbox/:id/translate", to: "inbox#translate",        as: :inbox_translate
  get  "inbox/:id/attachment/:blob_key", to: "inbox#download_attachment", as: :inbox_attachment
  get  "inbox/:id/attachment_preview/:blob_id", to: "inbox#preview_attachment", as: :inbox_attachment_preview
  post "inbox/analyze_link", to: "inbox#analyze_link", as: :inbox_analyze_link
  post "inbox/:id/feedback",      to: "inbox#feedback",       as: :inbox_feedback
  post "inbox/:id/reclassify",    to: "inbox#reclassify",     as: :inbox_reclassify
  post "inbox/:id/generate_reply", to: "inbox#generate_reply", as: :inbox_generate_reply
  post "inbox/bulk_delete",    to: "inbox#bulk_delete",    as: :inbox_bulk_delete
  post "inbox/bulk_trash",     to: "inbox#bulk_trash",     as: :inbox_bulk_trash
  post "inbox/bulk_to_kanban", to: "inbox#bulk_to_kanban", as: :inbox_bulk_to_kanban
  post "inbox/bulk_restore",   to: "inbox#bulk_restore",   as: :inbox_bulk_restore

  # Calendar
  get "calendar", to: "calendar#index"

  # Team management
  resources :team, only: %i[index show], controller: "team" do
    member do
      patch :update_role
    end
  end

  # Admin namespace
  namespace :admin do
    resources :imports, only: %i[index new create show] do
      member { get :download_errors; post :retry_errors }
    end
    patch "sheets_config",       to: "sheets_config#update", as: :sheets_config
    delete "sheets_config/clear", to: "sheets_config#clear",  as: :sheets_config_clear

    # eCountERP API 동기화 관리
    resources :ecount_sync, only: [ :index ] do
      collection { post :trigger }
    end

    # eCount 데이터 조회 메뉴 (품목 / 거래처 / 거래내역)
    namespace :ecount do
      resources :products,     only: %i[index show]
      resources :customers,    only: %i[index show]
      resources :transactions, only: %i[index]
    end

    # 중복 주문 병합
    resources :duplicate_orders, only: [ :index ] do
      collection { post :merge }
    end

    # Phase E: RFQ AI 학습 통계
    resources :rfq_stats, only: [ :index ]
  end

  # Gmail OAuth2
  scope "gmail/oauth" do
    get  "authorize",   to: "gmail_oauth#authorize",   as: :gmail_oauth_authorize
    get  "callback",    to: "gmail_oauth#callback",    as: :gmail_oauth_callback
    delete "disconnect/:id", to: "gmail_oauth#disconnect", as: :gmail_oauth_disconnect
  end

  # 발주처 (Clients)
  resources :clients do
    collection { get :search }
    resources :contact_persons, only: %i[new create edit update destroy]
  end

  # 거래처 (Suppliers) - destroy 제외 (발주 이력 보존)
  resources :suppliers, except: [ :destroy ] do
    collection { get :search }
    resources :contact_persons, only: %i[new create edit update destroy]
    resources :supplier_products, only: %i[create destroy]
  end

  # 프로젝트 (Projects)
  resources :projects do
    collection { get :search }
  end

  # 조직도 (Org Chart)
  get "org_chart", to: "org_chart#index", as: :org_chart

  namespace :org_chart do
    resources :countries, only: %i[index show new create edit update destroy]
    resources :companies, only: %i[index show new create edit update destroy] do
      resources :departments, only: %i[show new create edit update destroy]
    end
  end

  # 직원 폼 내 부서/직책 인라인 관리 (AJAX) — resources :employees 보다 먼저 선언해야 /employees/departments가 올바르게 라우팅됨
  namespace :employees do
    resources :departments,  only: %i[index create destroy]
    resources :job_titles,   only: %i[index create destroy]
  end

  # 직원 관리 (HR System)
  resources :employees do
    resources :visas,                only: %i[new create edit update destroy] do
      member { post :start_renewal }
    end
    resources :employment_contracts, only: %i[new create edit update destroy]
    resources :employee_assignments, only: %i[new create edit update destroy]
    resources :certifications,       only: %i[new create edit update destroy]
  end

  # 외부 담당자 전체 목록 + 상세
  resources :contact_persons, only: %i[index show] do
    collection do
      post :create_from_signature
    end
  end

  # 멘션 자동완성 (@ 입력 시 팀원 검색)
  get "/users/mention_suggestions", to: "users#mention_suggestions", as: :mention_suggestions

  # 통합 검색 (Command Palette)
  get "/search", to: "search#index", as: :search

  # 경영 리포트
  get "/reports",            to: "reports#index",      as: :reports
  get "/reports/export_csv", to: "reports#export_csv", as: :reports_export_csv
  get "/reports/export_pdf", to: "reports#export_pdf", as: :reports_export_pdf

  # CPO Agent Insights (dismiss/feedback)
  resources :agent_insights, only: [] do
    member do
      patch :dismiss
      patch :feedback
    end
  end

  # 알림 센터
  resources :notifications, only: %i[index] do
    collection { patch :read_all }
    member     { patch :read }
  end

  # 주문 일괄 처리 (Bulk Actions)
  scope "/orders", as: "orders" do
    resource :bulk, only: [], controller: "orders/bulk" do
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
    resources :email_accounts, only: %i[index new create destroy] do
      member { post :sync }
    end
    patch "profile", to: "profile#update"
    patch "locale", to: "profile#update_locale", as: :update_locale
    patch "theme",  to: "profile#update_theme",  as: :update_theme
    get "menu_permissions",    to: "menu_permissions#index",     as: :menu_permissions
    patch "menu_permissions",   to: "menu_permissions#update_all", as: :update_menu_permissions
    patch "notifications",      to: "notifications#update",        as: :notifications
    post  "notifications/test", to: "notifications#test",          as: :test_notifications
    patch "agent_trust/:insight_type", to: "agent_trust#toggle", as: :agent_trust_toggle
    patch "api_keys", to: "api_keys#update", as: :api_keys
    post  "api_keys/verify", to: "api_keys#verify", as: :verify_api_key
    resources :kanban_boards, except: [:show] do
      member do
        patch :reorder
        post :duplicate
      end
    end
    resources :card_statuses, except: %i[show new edit] do
      collection do
        patch :reorder
        post  :apply_theme  # 4개 테마 팔레트 일괄 적용
      end
      member { patch :inline_rename }
    end
    resources :kanban_columns, except: %i[show new edit] do
      collection { patch :reorder }
    end
  end
end
