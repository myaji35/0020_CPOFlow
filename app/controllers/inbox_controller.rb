class InboxController < ApplicationController
  # Rate limiting: AI API 호출은 사용자당 분당 최대 10회
  RATE_LIMIT_WINDOW = 60   # 초
  RATE_LIMIT_MAX    = 10   # 최대 호출 수

  before_action :check_rate_limit!, only: %i[translate analyze_link generate_reply]

  def index
    base_scope = Order.where.not(original_email_from: [ nil, "" ])
                      .includes(:user, :assignees, :client, :supplier, :project,
                                attachments_attachments: :blob)

    # Filter support: all (default), rfq (inbox only), converted (non-inbox)
    @current_filter = params[:filter].presence || "all"
    case @current_filter
    when "rfq"
      base_scope = base_scope.where(status: :inbox)
    when "uncertain"
      base_scope = base_scope.where(status: :inbox, rfq_status: Order.rfq_statuses[:rfq_uncertain])
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

    # reference_no 기준 그룹핑: 동일 발주번호 메일을 스레드로 묶음
    # key: reference_no (있으면) / "single_{id}" (없으면 단건)
    @grouped_orders = @all_orders
      .group_by { |o| o.reference_no.presence || "single_#{o.id}" }
      .sort_by { |_key, orders| orders.map(&:created_at).max }
      .reverse
      .to_h

    # Counts for sidebar badges (unfiltered, unsearched)
    email_scope = Order.where.not(original_email_from: [ nil, "" ])
    @count_all       = email_scope.count
    @count_rfq       = email_scope.where(status: :inbox).count
    @count_uncertain = email_scope.where(status: :inbox, rfq_status: Order.rfq_statuses[:rfq_uncertain]).count
    @count_converted = email_scope.where.not(status: :inbox).count
  end

  def show
    @order = Order.includes(attachments_attachments: :blob)
                  .find_by(source_email_id: params[:id]) ||
             Order.includes(attachments_attachments: :blob)
                  .find(params[:id])
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

  # AJAX: 사용자 RFQ 피드백 (맞음/아님)
  def feedback
    order = Order.find(params[:id])
    verdict = params[:verdict].to_s  # "confirmed" or "rejected"

    unless %w[confirmed rejected].include?(verdict)
      return render json: { error: "올바르지 않은 판정값입니다" }, status: :unprocessable_entity
    end

    Gmail::RfqFeedbackService.record!(order, current_user, verdict: verdict, note: params[:note])

    # confirmed 시 칸반 카드 자동 생성 (status 변경 없이 rfq_status만 업데이트됨)
    if verdict == "confirmed"
      RfqReplyDraftJob.perform_later(order.id)
    end

    render json: {
      status:     "ok",
      verdict:    verdict,
      rfq_status: order.reload.rfq_status,
      message:    verdict == "confirmed" ? "RFQ로 확정했습니다. 답변 초안을 생성 중입니다." : "제외 처리했습니다."
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  end

  # AJAX: 답변 초안 직접 생성 요청
  def generate_reply
    order = Order.find(params[:id])
    order.update_column(:reply_draft, nil)  # 기존 초안 삭제 후 재생성
    draft = Gmail::RfqReplyDraftService.generate!(order)

    if draft.present?
      render json: { status: "ok", draft: draft }
    else
      render json: { error: "답변 초안 생성에 실패했습니다." }, status: :unprocessable_entity
    end
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
