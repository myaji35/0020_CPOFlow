Rails.application.routes.draw do
  # AUDIT-009: registrations 라우트 제거 — 외부 sign_up 차단 (admin 초대 + Google OAuth 신규 가입만)
  devise_for :users, skip: [ :registrations ], controllers: {
    sessions: "users/sessions",
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  # Legal pages (ISS-320: Google OAuth Verification — unauthenticated)
  get "/privacy", to: "legal#privacy", as: :privacy_policy
  get "/terms",   to: "legal#terms",   as: :terms_of_service

  # AtoZ 직원 등록 대기 안내 — Employee 매칭 안 된 사용자 차단 안내 페이지
  get "/pending_approval", to: "users/pending#show", as: :pending_approval

  # 페르소나 전환 (admin 전용) — PATCH /persona/:key
  patch "persona/:key", to: "personas#update", as: :persona

  # ISS-352: Impersonation (직원 환경 가장) — admin 전용
  post   "impersonations",       to: "impersonations#create",  as: :impersonations
  get    "impersonations/enter", to: "impersonations#enter",   as: :impersonations_enter
  delete "impersonations",       to: "impersonations#destroy", as: :stop_impersonating

  authenticated :user do
    root to: "dashboard#index", as: :authenticated_root
  end

  root to: redirect("/users/sign_in")

  # Dashboard
  get  "dashboard",      to: "dashboard#index"
  post "dashboard/sync", to: "dashboard#sync_sheets", as: :sync_sheets

  # Kanban board (ISS-044: /orders/kanban 직관적 alias redirect)
  get "kanban",         to: "kanban#index"
  get "kanban/card/:id", to: "kanban#card", as: :kanban_card  # 단일 카드 partial (담당자 변경 후 부분 갱신)
  get "orders/kanban",  to: redirect("/kanban")
  patch "orders/:id/move", to: "kanban#move", as: :move_order
  post "kanban/merge", to: "kanban#merge", as: :kanban_merge
  patch "kanban/split/:id", to: "kanban#split", as: :kanban_split

  # Orders (full CRUD + nested resources)
  resources :orders do
    collection do
      get :preview_by_ref  # M3-4: 칸반 reference_no 호버 미니프리뷰
      get :price_history        # ISS-224: 동일 조합 직전 단가 조회
      get :pricing_suggestion   # ISS-308: OrderQuote 이력 단가·공급사 추천
      post   :save_filter            # ISS-229
      delete :delete_saved_filter    # ISS-229
    end
    resources :tasks, only: %i[create update destroy] do
      member do
        patch :feedback  # ISS-293: RFP 자동 생성 태스크 👍/👎 피드백
      end
    end
    resources :quote_items, only: %i[index create update destroy], controller: "order_quote_items"
    resources :comments, only: %i[create destroy]
    resources :assignments, only: %i[create destroy]
    resources :order_quotes, only: %i[new create destroy] do
      member { patch :select }
    end
    resource :flow, only: [ :show ], controller: "order_flows"
    member do
      patch :move_status
      patch :quick_update
      patch :update_tracking
      post  :attach
      post  :attach_from_url
      # ISS-315: GET prefetch / 외부 링크 클릭으로 RoutingError 자주 발생
      # → DELETE 정상 호출 + GET fallback (302 redirect to order, 안전)
      match "detach/:blob_id", action: :detach, via: %i[delete get], as: :detach
      get  "pdf/quote",          to: "orders/pdf#quote",           as: :pdf_quote
      get  "pdf/purchase_order", to: "orders/pdf#purchase_order",  as: :pdf_purchase_order
      get  "attachment_preview/:blob_id", action: :preview_attachment, as: :attachment_preview
      post :urgent_email_draft   # ISS-328: 긴급 견적 의뢰 메일 초안

      # ISS-354 Phase 2 Wave 3 — 컴포넌트 B 발신자 호버 + 리마인드
      get  :mention_sender_hover
      post :mention_remind_all
      post "mention_remind_one/:user_id", action: :mention_remind_one, as: :mention_remind_one
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

  # 휴지통 — soft-deleted Order 복원/영구삭제
  get    "trash",                to: "trash#index",            as: :trash
  post   "trash/:id/restore",    to: "trash#restore",          as: :restore_trash
  delete "trash/:id",            to: "trash#destroy",          as: :destroy_trash
  delete "trash",                to: "trash#empty",            as: :empty_trash

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
  post "inbox/bulk_all_uncertain_to_kanban", to: "inbox#bulk_all_uncertain_to_kanban", as: :inbox_bulk_all_uncertain_to_kanban
  post "inbox/bulk_restore",   to: "inbox#bulk_restore",   as: :inbox_bulk_restore

  # Calendar
  get "calendar", to: "calendar#index"

  # Team management
  resources :team, only: %i[index show], controller: "team" do
    member do
      patch :update_role
    end
  end

  # ── LAB (실험적 기능 — admin/manager 전용) ──────────────────
  namespace :lab do
    resources :rfq_auto, only: %i[index show] do
      collection do
        post :sandbox          # 새 샌드박스 Order 생성
        get  :import_suppliers # CSV/표 import 폼
        post :import_suppliers # CSV/표 import 처리
      end
      member do
        post   :analyze                                # 분석 실행
        post   :apply                                  # 결과를 Order에 반영
        post   :feedback                               # 사용자 피드백
        post   :upload                                 # 첨부 업로드 (+ 즉시 분석 옵션)
        post   :select_supplier                        # D-5 공급사 선택/해제 (토글)
        post   :send_rfq_emails                        # D-6 선택된 공급사들에게 RFQ 이메일 발송
        delete "attachments/:attachment_id", to: "rfq_auto#destroy_attachment", as: :attachment
      end
    end
  end

  # Admin namespace
  namespace :admin do
    resources :agent_runs, only: %i[index]
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
    resources :rfq_stats, only: [ :index ] do
      collection { post :reclassify_mismatches }
    end

    # ISS-231: 사용자 피드백 리뷰 관리
    resources :reviews, only: %i[index] do
      member { patch :transition }
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
    # ISS-332: 경고장 (현장 배정 대체)
    resources :warnings do
      member { patch :acknowledge }
    end
  end

  # ISS-305: 휴가/근태 Leave 모듈
  resources :leaves do
    member do
      patch :approve_manager
      patch :approve_admin
      patch :reject
      patch :cancel
    end
    collection do
      get :calendar  # FullCalendar JSON
      get :balance   # 직원별 잔여일수
    end
  end

  # 외부 담당자 전체 목록 + 상세
  resources :contact_persons, only: %i[index show] do
    collection do
      post :create_from_signature
      get  :search
    end
  end

  # 멘션 자동완성 (@ 입력 시 팀원 검색)
  get "/users/mention_suggestions", to: "users#mention_suggestions", as: :mention_suggestions
  get "/users/search",              to: "users#search",              as: :search_users

  # 통합 검색 (Command Palette)
  get "/search", to: "search#index", as: :search

  # 경영 리포트
  get "/reports",            to: "reports#index",      as: :reports
  get "/reports/export_csv", to: "reports#export_csv", as: :reports_export_csv
  get "/reports/export_pdf", to: "reports#export_pdf", as: :reports_export_pdf

  # 사용자 피드백 리뷰 (공개 접근)
  resources :reviews, only: %i[new create]

  # Admin namespace에 reviews 추가
  # (admin namespace 블록 바깥에 별도 선언)

  # API namespace (Command Center 폴링용)
  namespace :api do
    get "reviews", to: "reviews#index"
  end

  # CPO Agent Insights (목록 + dismiss/feedback)
  resources :agent_insights, only: %i[index] do
    member do
      patch :dismiss
      patch :feedback
    end
  end

  # 알림 센터
  resources :notifications, only: %i[index] do
    collection { patch :read_all }
    member do
      patch :read
      patch :acknowledge  # ISS-353 Phase 1: 멘션 [✓ 확인] 클릭
      patch :view         # ISS-353 Phase 1: 뷰포트 5초 노출 자동 기록
    end
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

  resources :attachment_quote_analyses, only: %i[create] do
    member { post :reanalyze }
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
    patch "notification_preferences", to: "profile#update_notification_preferences", as: :update_notification_preferences
    get "menu_permissions",    to: "menu_permissions#index",     as: :menu_permissions
    patch "menu_permissions",   to: "menu_permissions#update_all", as: :update_menu_permissions
    patch "notifications",      to: "notifications#update",        as: :notifications
    post  "notifications/test", to: "notifications#test",          as: :test_notifications
    patch "agent_trust/:insight_type", to: "agent_trust#toggle", as: :agent_trust_toggle
    patch "api_keys", to: "api_keys#update", as: :api_keys
    post  "api_keys/verify", to: "api_keys#verify", as: :verify_api_key
    resources :checklist_items, except: %i[show new edit]  # ISS-330
    resources :kanban_boards, except: [ :show ] do
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
    resources :tracking_codes, except: %i[show new edit] do
      collection { patch :reorder }
    end
  end
end
