class InboxController < ApplicationController
  # Rate limiting: AI API 호출은 사용자당 분당 최대 10회
  RATE_LIMIT_WINDOW = 60   # 초
  RATE_LIMIT_MAX    = 10   # 최대 호출 수

  before_action :check_rate_limit!, only: %i[translate analyze_link]
  def index
    base_scope = Order.where.not(original_email_from: [ nil, "" ])
                      .includes(:user, :assignees, :client, :supplier, :project)

    # Filter support: all (default), rfq (inbox only), converted (non-inbox)
    @current_filter = params[:filter].presence || "all"
    case @current_filter
    when "rfq"
      base_scope = base_scope.where(status: :inbox)
    when "converted"
      base_scope = base_scope.where.not(status: :inbox)
    end

    # Search support
    @search_query = params[:q].to_s.strip
    if @search_query.present?
      search_term = "%#{@search_query}%"
      base_scope = base_scope.where(
        "original_email_subject LIKE :q OR original_email_from LIKE :q OR customer_name LIKE :q OR title LIKE :q",
        q: search_term
      )
    end

    @all_orders = base_scope.order(created_at: :desc).limit(100)

    # Counts for sidebar badges (unfiltered, unsearched)
    email_scope = Order.where.not(original_email_from: [ nil, "" ])
    @count_all       = email_scope.count
    @count_rfq       = email_scope.where(status: :inbox).count
    @count_converted = email_scope.where.not(status: :inbox).count
  end

  def show
    @order = Order.find_by(source_email_id: params[:id]) ||
             Order.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to inbox_path, alert: "해당 이메일을 찾을 수 없습니다."
  end

  def convert_to_order
    @order = Order.find(params[:id])
    if @order.update(status: :reviewing)
      Activity.create!(order: @order, user: current_user, action: "moved_to_kanban")
      redirect_to kanban_path, notice: t("inbox.convert_success")
    else
      redirect_back fallback_location: inbox_path, alert: "Failed to convert."
    end
  end

  # Manual sync trigger (called from Inbox UI "Sync" button)
  def sync
    accounts = current_user.email_accounts.where(connected: true)
    if accounts.any?
      accounts.each { |acc| EmailSyncJob.perform_later(account_id: acc.id) }
      render json: { status: "ok", message: "Sync queued for #{accounts.count} account(s)" }
    else
      render json: { status: "error", message: "No connected accounts" }, status: :unprocessable_entity
    end
  end

  # AJAX: 특정 Order의 번역본 반환 (없으면 번역 후 저장)
  # ?force=true 파라미터 시 기존 번역 무시하고 재번역
  def translate
    order = Order.find(params[:id])
    require "net/http"

    if params[:force] == "true"
      # 기존 번역 초기화 후 강제 재번역
      order.update_columns(translated_subject: nil, translated_body: nil)
    end

    TranslationService.translate_order!(order)

    render json: {
      translated_subject: order.translated_subject,
      translated_body:    order.translated_body
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  end

  # AJAX: 이메일 본문 링크 URL 내용 추출 + AI 요약
  def analyze_link
    require "net/http"
    url = params[:url].to_s.strip

    if url.blank? || !url.match?(/\Ahttps?:\/\//i)
      return render json: { success: false, error: "유효하지 않은 URL입니다" }, status: :unprocessable_entity
    end

    result = LinkAnalyzerService.analyze(url)
    render json: result
  rescue => e
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  private

  # 간단한 메모리 기반 Rate Limiter (Rails.cache 활용)
  def check_rate_limit!
    key = "rate_limit:inbox_ai:#{current_user.id}"
    count = Rails.cache.read(key).to_i

    if count >= RATE_LIMIT_MAX
      render json: {
        error: "요청이 너무 많습니다. #{RATE_LIMIT_WINDOW}초 후에 다시 시도해주세요.",
        retry_after: RATE_LIMIT_WINDOW
      }, status: :too_many_requests
      return
    end

    Rails.cache.write(key, count + 1, expires_in: RATE_LIMIT_WINDOW.seconds)
  end

  public

  # 첨부파일 다운로드 (ActiveStorage blob proxy)
  def download_attachment
    order = Order.find(params[:id])
    blob_key = params[:blob_key]

    # Find the attachment blob by key
    attachment = order.attachments.find { |a| a.blob.key == blob_key }
    if attachment
      redirect_to rails_blob_path(attachment.blob, disposition: "attachment"), allow_other_host: false
    else
      render json: { error: "첨부파일을 찾을 수 없습니다" }, status: :not_found
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  end
end
