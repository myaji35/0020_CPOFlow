class InboxController < ApplicationController
  # Rate limiting: AI API 호출은 사용자당 분당 최대 10회
  RATE_LIMIT_WINDOW = 60   # 초
  RATE_LIMIT_MAX    = 10   # 최대 호출 수

  before_action :check_rate_limit!, only: %i[translate analyze_link generate_reply]

  PER_PAGE = 30

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

    # Pagination: 30건씩 로드 (UAE 느린 네트워크 대응)
    @page = [ params[:page].to_i, 1 ].max
    @total_filtered = base_scope.count
    @all_orders = base_scope.order(created_at: :desc)
                            .offset((@page - 1) * PER_PAGE)
                            .limit(PER_PAGE)
    @total_pages = (@total_filtered.to_f / PER_PAGE).ceil

    # reference_no 기준 그룹핑: 동일 발주번호 메일을 스레드로 묶음
    # key: reference_no (있으면) / "single_{id}" (없으면 단건)
    @grouped_orders = @all_orders
      .group_by { |o| o.reference_no.presence || "single_#{o.id}" }
      .sort_by { |_key, orders| orders.map(&:created_at).max }
      .reverse
      .to_h

    # Counts for sidebar badges — 단일 쿼리로 통합 (4회 → 1회)
    inbox_val     = Order.statuses[:inbox]
    uncertain_val = Order.rfq_statuses[:rfq_uncertain]
    email_scope = Order.where.not(original_email_from: [ nil, "" ])
    counts = email_scope.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("SUM(CASE WHEN status = #{inbox_val} THEN 1 ELSE 0 END)"),
      Arel.sql("SUM(CASE WHEN status = #{inbox_val} AND rfq_status = #{uncertain_val} THEN 1 ELSE 0 END)"),
      Arel.sql("SUM(CASE WHEN status != #{inbox_val} THEN 1 ELSE 0 END)")
    )
    @count_all, @count_rfq, @count_uncertain, @count_converted = counts.map(&:to_i)
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
  # Ariba 링크인 경우 AribaFetchJob으로 비동기 문서 수집
  def analyze_link
    require "net/http"
    url = params[:url].to_s.strip
    order_id = params[:order_id]

    if url.blank? || !url.match?(/\Ahttps?:\/\//i)
      return render json: { success: false, error: "유효하지 않은 URL입니다" }, status: :unprocessable_entity
    end

    # Ariba 링크 감지 → 비동기 문서 수집 (수동 요청이므로 force: true)
    if url.match?(Sap::AribaScraperService::ARIBA_LINK_PATTERN) && order_id.present?
      AribaFetchJob.perform_later(order_id: order_id.to_i, force: true)
      return render json: {
        success: true,
        ariba: true,
        summary: "Ariba 포털 문서 수집을 시작했습니다. 잠시 후 첨부파일 목록을 새로고침하세요."
      }
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

  # Excel → HTML 테이블 변환 (roo gem)
  def build_excel_preview_html(spreadsheet, filename)
    sheets_html = spreadsheet.sheets.map.with_index do |sheet_name, idx|
      spreadsheet.default_sheet = sheet_name
      first_row = spreadsheet.first_row
      last_row  = [spreadsheet.last_row || 0, 500].min  # 최대 500행
      first_col = spreadsheet.first_column
      last_col  = spreadsheet.last_column

      next "" unless first_row && last_row && first_col && last_col

      rows_html = (first_row..last_row).map do |row|
        cells = (first_col..last_col).map do |col|
          val = spreadsheet.cell(row, col)
          tag = row == first_row ? "th" : "td"
          "<#{tag}>#{ERB::Util.html_escape(val.to_s)}</#{tag}>"
        end.join
        "<tr>#{cells}</tr>"
      end.join

      tab_id = "sheet-#{idx}"
      <<~HTML
        <div class="sheet-tab" data-sheet="#{tab_id}" style="display:#{idx == 0 ? 'block' : 'none'}">
          <div style="overflow-x:auto;">
            <table>#{rows_html}</table>
          </div>
        </div>
      HTML
    end.join

    tab_buttons = spreadsheet.sheets.map.with_index do |name, idx|
      active = idx == 0 ? "active" : ""
      "<button class='tab-btn #{active}' onclick='switchSheet(#{idx})'>#{ERB::Util.html_escape(name)}</button>"
    end.join

    <<~HTML
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><title>#{ERB::Util.html_escape(filename)}</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #fff; color: #1f2937; }
        .toolbar { position: sticky; top: 0; z-index: 10; background: #f8fafc; border-bottom: 1px solid #e2e8f0;
                   padding: 8px 16px; display: flex; align-items: center; justify-content: space-between; }
        .toolbar h1 { font-size: 13px; font-weight: 600; color: #334155; }
        .tabs { display: flex; gap: 2px; padding: 0 16px; background: #f1f5f9; border-bottom: 1px solid #e2e8f0; }
        .tab-btn { padding: 6px 14px; font-size: 12px; border: none; background: transparent; color: #64748b;
                   cursor: pointer; border-bottom: 2px solid transparent; }
        .tab-btn.active { color: #0369a1; border-bottom-color: #0369a1; font-weight: 600; background: #fff; }
        .tab-btn:hover { background: #e2e8f0; }
        table { border-collapse: collapse; width: 100%; font-size: 12px; }
        th, td { border: 1px solid #e2e8f0; padding: 4px 8px; text-align: left; white-space: nowrap; max-width: 300px; overflow: hidden; text-overflow: ellipsis; }
        th { background: #f1f5f9; font-weight: 600; color: #334155; position: sticky; top: 0; }
        tr:hover td { background: #f0f9ff; }
        tr:nth-child(even) td { background: #f8fafc; }
        tr:hover td, tr:nth-child(even):hover td { background: #e0f2fe; }
      </style>
      </head><body>
        <div class="toolbar">
          <h1>📄 #{ERB::Util.html_escape(filename)}</h1>
        </div>
        #{"<div class='tabs'>#{tab_buttons}</div>" if spreadsheet.sheets.size > 1}
        #{sheets_html}
        <script>
          function switchSheet(idx) {
            document.querySelectorAll('.sheet-tab').forEach((el, i) => { el.style.display = i === idx ? 'block' : 'none'; });
            document.querySelectorAll('.tab-btn').forEach((el, i) => { el.classList.toggle('active', i === idx); });
          }
        </script>
      </body></html>
    HTML
  end

  public

  # 첨부파일 미리보기 (xlsx/xls → HTML 테이블 변환, 기타 → inline redirect)
  def preview_attachment
    order = Order.find(params[:id])
    blob = ActiveStorage::Blob.find(params[:blob_id])

    content_type = blob.content_type.to_s

    # Excel 파일: roo gem으로 HTML 테이블 변환
    if content_type.include?("spreadsheet") || content_type.include?("excel") ||
       blob.filename.to_s.match?(/\.xlsx?\z/i)
      blob.open do |tempfile|
        spreadsheet = Roo::Spreadsheet.open(tempfile.path, extension: File.extname(blob.filename.to_s))
        html = build_excel_preview_html(spreadsheet, blob.filename.to_s)
        render html: html.html_safe, layout: false
      end
    # HTML content → 직접 읽어서 렌더링 (iframe 내 redirect 다운로드 방지)
    elsif content_type.include?("html")
      blob.open do |tempfile|
        html_content = File.read(tempfile.path, encoding: "UTF-8")
        render html: html_content.html_safe, layout: false
      end
    # PDF, 이미지 → inline redirect
    elsif content_type.include?("pdf") || content_type.start_with?("image/")
      redirect_to rails_blob_path(blob, disposition: "inline"), allow_other_host: false
    else
      redirect_to rails_blob_path(blob, disposition: "attachment"), allow_other_host: false
    end
  rescue ActiveRecord::RecordNotFound
    render html: "<p style='padding:2rem;color:#666;'>첨부파일을 찾을 수 없습니다.</p>".html_safe, layout: false, status: :not_found
  rescue => e
    render html: "<p style='padding:2rem;color:#c00;'>미리보기 오류: #{ERB::Util.html_escape(e.message)}</p>".html_safe, layout: false, status: :internal_server_error
  end

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
