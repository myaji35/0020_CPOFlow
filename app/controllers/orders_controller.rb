class OrdersController < ApplicationController
  include AttachmentPreviewable

  before_action :set_order, only: %i[show edit update destroy move_status quick_update preview_attachment attach attach_from_url detach]

  def index
    @orders = Order.all.includes(:assignees, :tasks, :user, :client, :project, :supplier, :card_status).by_due_date

    # 기존 필터
    @orders = @orders.where(status: params[:status]) if params[:status].present?
    @orders = @orders.where("orders.title LIKE ? OR orders.customer_name LIKE ?",
                            "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?

    # 거래내역 추적 필터 (FR-01)
    @orders = @orders.where(client_id: params[:client_id])     if params[:client_id].present?
    @orders = @orders.where(supplier_id: params[:supplier_id]) if params[:supplier_id].present?
    @orders = @orders.where(project_id: params[:project_id])   if params[:project_id].present?
    @orders = @orders.joins(:assignments).where(assignments: { employee_id: params[:employee_id] }) if params[:employee_id].present?

    # 납기일 범위 필터
    @orders = @orders.where(due_date: params[:due_from]..) if params[:due_from].present?
    @orders = @orders.where(due_date: ..params[:due_to])   if params[:due_to].present?

    # 기간 필터
    case params[:period]
    when "this_month"
      @orders = @orders.where(created_at: Time.current.beginning_of_month..)
    when "3months"
      @orders = @orders.where(created_at: 3.months.ago..)
    when "this_year"
      @orders = @orders.where(created_at: Time.current.beginning_of_year..)
    when "custom"
      @orders = @orders.where(created_at: params[:date_from]..) if params[:date_from].present?
      @orders = @orders.where(created_at: ..Date.parse(params[:date_to]).end_of_day) if params[:date_to].present?
    end

    # 필터 드롭다운용 데이터 (5분 캐시)
    @filter_clients   = Rails.cache.fetch("filter/clients",   expires_in: 5.minutes) { Client.active.by_name.to_a }
    @filter_suppliers = Rails.cache.fetch("filter/suppliers",  expires_in: 5.minutes) { Supplier.active.by_name.to_a }
    @filter_projects  = Rails.cache.fetch("filter/projects",   expires_in: 5.minutes) { Project.active.by_name.to_a }
    @filter_employees = Rails.cache.fetch("filter/employees",  expires_in: 5.minutes) { Employee.active.by_name.to_a }

    @total_count = @orders.count

    # KPI 카드용 집계
    @kpi_in_progress = @orders.where.not(status: [:get_grn, :give_up, :done]).count
    @kpi_completed   = @orders.where(status: [:get_grn, :done]).count
    @kpi_overdue     = @orders.where("due_date < ? AND status NOT IN (?, ?, ?)", Date.today, Order.statuses[:get_grn], Order.statuses[:give_up], Order.statuses[:done]).count

    @orders = @orders.limit(50).offset((params[:page].to_i > 0 ? params[:page].to_i - 1 : 0) * 50)
    @current_page = [ params[:page].to_i, 1 ].max
    @total_pages = (@total_count / 50.0).ceil
  end

  def show
    @tasks    = @order.tasks.by_due.includes(:assignee)
    @comments = @order.comments.chronological.includes(:user)
    @activities = @order.activities.recent.includes(:user).limit(20)
    @order.attachments.includes(:blob).load  # 첨부파일 eager load
    @team_members = Employee.active.by_name

    # CPO Agent: 비동기 분석 트리거 + 기존 Insight 로드
    AgentInsightJob.perform_later(@order.id, current_user.id)
    @agent_insights = @order.agent_insights.active.order(severity: :desc).limit(3)
    # 관련 메일 스레드: sub_orders 우선, 없으면 reference_no 기반 fallback
    @thread_orders = if @order.sub_orders.exists?
      @order.sub_orders.order(created_at: :asc)
    elsif @order.parent_order_id.present?
      Order.where(parent_order_id: @order.parent_order_id)
           .or(Order.where(id: @order.parent_order_id))
           .where.not(id: @order.id)
           .order(created_at: :asc)
    elsif @order.reference_no.present?
      Order.where(reference_no: @order.reference_no)
           .where.not(id: @order.id)
           .order(created_at: :asc)
    else
      Order.none
    end
  end

  def new
    @order = Order.new
    @order.due_date = 30.days.from_now
    @board = if params[:board_id].present?
      KanbanBoard.find_by(id: params[:board_id])
    else
      KanbanBoard.default_board.first || KanbanBoard.ensure_default!
    end
    @order.kanban_board_id = @board.id
  end

  def create
    @order = Order.new(order_params)
    @order.user = current_user
    @order.status = :new_rfq
    @order.rfq_status = :rfq_triage
    @order.kanban_board_id ||= (KanbanBoard.default_board.first || KanbanBoard.ensure_default!).id

    if @order.save
      # 첨부파일 처리
      if params.dig(:order, :files).present?
        @order.attachments.attach(Array(params[:order][:files]))
      end
      # 담당자 배정 (@멘션)
      if params.dig(:order, :assigned_employee_id).present?
        emp = Employee.find_by(user_id: params[:order][:assigned_employee_id])
        Assignment.create(order: @order, employee: emp) if emp
      end
      Activity.create!(order: @order, user: current_user, action: "created")
      redirect_to kanban_path(board_id: @order.kanban_board_id), notice: is_purchase_board? ? "발주가 등록되었습니다." : "카드가 등록되었습니다."
    else
      @board = @order.kanban_board || KanbanBoard.default_board.first
      render :new, status: :unprocessable_entity
    end
  end

  private def is_purchase_board?
    board = @order&.kanban_board
    board.nil? || board.is_default? || board.board_type == "purchase"
  end
  public

  def edit; end

  # ISS-229: POST /orders/save_filter
  # 현재 쿼리 파라미터를 User.saved_filters[:orders]에 저장
  def save_filter
    name = params[:filter_name].to_s.strip
    if name.blank?
      return redirect_back fallback_location: orders_path, alert: "필터 이름을 입력하세요"
    end
    filter_params = params.except(:controller, :action, :filter_name, :authenticity_token, :commit, :_method)
                          .permit!.to_h.reject { |_, v| v.blank? }
    if filter_params.empty?
      return redirect_back fallback_location: orders_path, alert: "저장할 필터 조건이 없습니다"
    end
    current_user.add_saved_filter("orders", name, filter_params)
    redirect_to orders_path(filter_params), notice: "필터 '#{name}' 저장되었습니다"
  end

  # ISS-229: DELETE /orders/saved_filter?name=...
  def delete_saved_filter
    name = params[:name].to_s
    current_user.remove_saved_filter("orders", name)
    redirect_back fallback_location: orders_path, notice: "필터 '#{name}' 삭제되었습니다"
  end

  # ISS-224: GET /orders/price_history
  # params: client_id, supplier_id, item_name (모두 optional, 2개 이상 있을 때만 의미 있음)
  # 동일 조합의 최근 주문 단가/일자 반환
  def price_history
    scope = Order.where.not(estimated_value: [ nil, 0 ])
    scope = scope.where(client_id: params[:client_id])   if params[:client_id].present?
    scope = scope.where(supplier_id: params[:supplier_id]) if params[:supplier_id].present?
    if params[:item_name].present?
      item_like = "%#{params[:item_name].to_s.strip}%"
      scope = scope.where("item_name LIKE ?", item_like)
    end
    entries = scope.order(created_at: :desc).limit(5).map do |o|
      {
        id:           o.id,
        title:        o.title,
        item_name:    o.item_name,
        quantity:     o.quantity,
        unit_price:   (o.quantity.to_i > 0 ? (o.estimated_value.to_f / o.quantity).round(2) : nil),
        total:        o.estimated_value.to_f,
        currency:     o.currency,
        client:       o.client&.name,
        supplier:     o.supplier&.name,
        created_at:   o.created_at.strftime("%Y-%m-%d"),
        path:         order_path(o)
      }
    end
    render json: { count: entries.size, entries: entries }
  end

  def update
    # ISS-203: 감사 대상 필드 before-값 캡처
    audit_before = audited_snapshot(@order)

    if @order.update(order_params)
      # ISS-203: 실제 변경된 필드만 activity로 기록
      log_field_changes(@order, audit_before)
      # 필드 변경이 없었다면 generic "updated" activity는 기록하지 않음 (노이즈 방지)
      Activity.create!(order: @order, user: current_user, action: "updated") if audit_before.empty?
      redirect_to @order, notice: t("orders.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy

    respond_to do |format|
      format.html { redirect_to kanban_path, notice: t("orders.delete_success") }
      format.json { render json: { success: true } }
    end
  end

  def move_status
    old_status = @order.status
    new_status = params[:status]

    if @order.update(status: new_status)
      Activity.create!(
        order: @order,
        user: current_user,
        action: "status_changed",
        from_status: Order.statuses[old_status],
        to_status: Order.statuses[@order.status]
      )

      # 동일 gmail_thread_id의 inbox 상태 Order도 함께 변경
      synced_count = sync_thread_siblings_status(new_status)

      notice_msg = t("orders.status_updated", status: t("orders.status.#{new_status}", default: new_status))
      notice_msg += " (연관 #{synced_count}건도 함께 변경됨)" if synced_count > 0
      redirect_back fallback_location: kanban_path, notice: notice_msg
    else
      redirect_back fallback_location: kanban_path, alert: "Failed to update status."
    end
  end

  def quick_update
    permitted = params.require(:order).permit(:due_date, :status, :rfq_no, :quo_no, :po_no)
    if @order.update(permitted)
      Activity.create!(order: @order, user: current_user, action: "updated")
      render json: { success: true }
    else
      render json: { success: false, errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /orders/:id/attach — 첨부파일 수동 추가
  MAX_FILE_SIZE = 25.megabytes

  def attach
    files = params[:files]
    if files.blank?
      respond_to do |format|
        format.html { redirect_back fallback_location: @order, alert: "파일을 선택해 주세요." }
        format.json { render json: { success: false, error: "파일을 선택해 주세요." }, status: :unprocessable_entity }
      end
      return
    end

    file_list = Array(files)
    oversized = file_list.select { |f| f.size > MAX_FILE_SIZE }
    if oversized.any?
      names = oversized.map { |f| "#{f.original_filename} (#{ActiveSupport::NumberHelper.number_to_human_size(f.size)})" }.join(", ")
      msg = "파일 크기 초과 (최대 25MB): #{names}"
      respond_to do |format|
        format.html { redirect_back fallback_location: @order, alert: msg }
        format.json { render json: { success: false, error: msg }, status: :unprocessable_entity }
      end
      return
    end

    @order.attachments.attach(file_list)
    Activity.create!(order: @order, user: current_user, action: "attachment_added")

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "drawer-panel-#{@order.id}-attachments",
          partial: "orders/drawer_attachments", locals: { order: @order.reload, initial_render: false }
        )
      }
      format.html { redirect_back fallback_location: @order, notice: "#{file_list.size}개 파일이 첨부되었습니다." }
      format.json { render json: { success: true, count: file_list.size, message: "#{file_list.size}개 파일 첨부 완료" } }
    end
  end

  # POST /orders/:id/attach_from_url — URL에서 파일 다운로드 후 첨부
  def attach_from_url
    url = params[:url].to_s.strip
    if url.blank? || !url.match?(/\Ahttps?:\/\//i)
      return render_attach_error("유효하지 않은 URL입니다.")
    end

    # Google Drive 폴더 → 폴더 내 파일 전부 다운로드
    if url.match?(%r{drive\.google\.com/drive/folders/([a-zA-Z0-9_-]+)})
      folder_id = $1
      return attach_gdrive_folder(folder_id)
    end

    # Google Drive 파일 URL 자동 변환
    gdrive_file_id = extract_gdrive_file_id(url)
    if gdrive_file_id
      url = "https://drive.google.com/uc?export=download&confirm=t&id=#{gdrive_file_id}"
    end

    begin
      response = fetch_url_with_redirect(url)

      unless response.is_a?(Net::HTTPSuccess)
        return render_attach_error("다운로드 실패 (HTTP #{response.code})")
      end

      content_type = response["Content-Type"]&.split(";")&.first || "application/octet-stream"
      # Google Drive 바이러스 스캔 confirm 페이지 대응
      if content_type.include?("text/html") && gdrive_file_id && response.body.include?("download_warning")
        confirm_token = response.body.match(/confirm=([^&"]+)/)[1] rescue "t"
        url = "https://drive.google.com/uc?export=download&confirm=#{confirm_token}&id=#{gdrive_file_id}"
        response = fetch_url_with_redirect(url)
        content_type = response["Content-Type"]&.split(";")&.first || "application/octet-stream"
      end
      # HTML 반환 = 파일이 아닌 웹페이지 (로그인 필요, 비공개 등)
      if content_type.include?("text/html") && !url.match?(/\.html?\z/i)
        return render_attach_error("파일을 다운로드할 수 없습니다. 파일이 '링크가 있는 모든 사용자' 공유인지 확인하세요.")
      end

      # 파일명 결정: Content-Disposition > URL 경로 > fallback
      filename = nil
      if response["Content-Disposition"]
        match = response["Content-Disposition"].match(/filename[*]?=(?:UTF-8''|"?)([^";]+)/i)
        filename = match[1].strip if match
      end
      uri = URI.parse(url) rescue nil
      filename ||= uri ? File.basename(uri.path).presence : nil
      filename = "download_#{Time.current.to_i}" if filename.blank? || filename == "/"
      filename = URI.decode_www_form_component(filename) rescue filename

      content_type = response["Content-Type"]&.split(";")&.first || "application/octet-stream"

      @order.attachments.attach(
        io: StringIO.new(response.body),
        filename: filename,
        content_type: content_type
      )
      Activity.create!(order: @order, user: current_user, action: "attachment_added")

      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "drawer-panel-#{@order.id}-attachments",
            partial: "orders/drawer_attachments", locals: { order: @order.reload, initial_render: false }
          )
        }
        format.json { render json: { success: true, filename: filename } }
      end
    rescue => e
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.json { render json: { error: e.message }, status: :internal_server_error }
      end
    end
  end

  # DELETE /orders/:id/detach/:blob_id — 첨부파일 삭제
  def detach
    attachment = @order.attachments.find { |a| a.blob_id == params[:blob_id].to_i }
    if attachment
      attachment.purge
      Activity.create!(order: @order, user: current_user, action: "attachment_removed")
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            "drawer-panel-#{@order.id}-attachments",
            partial: "orders/drawer_attachments", locals: { order: @order.reload, initial_render: false }
          )
        }
        format.html { redirect_to @order, notice: "첨부파일이 삭제되었습니다." }
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @order, alert: "첨부파일을 찾을 수 없습니다." }
        format.json { render json: { success: false }, status: :not_found }
      end
    end
  end

  def preview_attachment
    blob = ActiveStorage::Blob.find(params[:blob_id])
    preview_blob(blob)
  rescue ActiveRecord::RecordNotFound
    render html: "<p style='padding:2rem;color:#666;'>첨부파일을 찾을 수 없습니다.</p>".html_safe, layout: false, status: :not_found
  rescue => e
    render html: "<p style='padding:2rem;color:#c00;'>미리보기 오류: #{ERB::Util.html_escape(e.message)}</p>".html_safe, layout: false, status: :internal_server_error
  end

  # Procurement Ontology M3 — 칸반 reference_no 호버 미니프리뷰
  def preview_by_ref
    ref = params[:ref].to_s.strip
    return head(:bad_request) if ref.blank?
    data = Rails.cache.fetch("refno_preview/#{ref}", expires_in: 5.minutes) do
      orders = Order.where(reference_no: ref).order(:created_at).limit(5).to_a
      if orders.any?
        g = OrderGraphBuilder.new(orders.first, depth: 1, include_suggested: false).call
        {
          ref: ref,
          count: orders.size,
          nodes: g[:nodes].size,
          edges: g[:edges].size,
          first_id: orders.first.id,
          titles: orders.map(&:title)
        }
      else
        { ref: ref, count: 0, nodes: 0, edges: 0, first_id: nil, titles: [] }
      end
    end
    render partial: "orders/refno_preview", locals: { data: data }
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end

  # ISS-203: 감사 대상 필드 (조달 컴플라이언스 관점)
  AUDITED_FIELDS = %w[
    estimated_value quantity currency due_date supplier_id client_id project_id
    po_no rfq_no quo_no payment_terms delivery_location item_name title
  ].freeze

  def audited_snapshot(order)
    AUDITED_FIELDS.each_with_object({}) { |f, h| h[f] = order.read_attribute(f) }
  end

  def log_field_changes(order, before)
    before.each do |field, old_val|
      new_val = order.read_attribute(field)
      next if old_val.to_s == new_val.to_s
      Activity.create!(
        order:      order,
        user:       current_user,
        action:     "field_changed",
        field:      field,
        old_value:  old_val.to_s,
        new_value:  new_val.to_s
      )
    end
  end

  def render_attach_error(msg)
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "drawer-panel-#{@order.id}-attachments",
          partial: "orders/drawer_attachments", locals: { order: @order.reload, initial_render: false, flash_error: msg }
        )
      }
      format.json { render json: { error: msg }, status: :unprocessable_entity }
      format.html { redirect_back fallback_location: @order, alert: msg }
    end
  end

  # Google Drive 폴더 내 파일 전부 다운로드하여 첨부
  def attach_gdrive_folder(folder_id)
    # embeddedfolderview로 파일 ID 목록 추출
    embed_url = "https://drive.google.com/embeddedfolderview?id=#{folder_id}"
    embed_res = fetch_url_with_redirect(embed_url)
    unless embed_res.is_a?(Net::HTTPSuccess)
      return render_attach_error("Google Drive 폴더에 접근할 수 없습니다. 공유 설정을 확인하세요.")
    end

    file_ids = embed_res.body.scan(%r{drive\.google\.com/file/d/([a-zA-Z0-9_-]+)}).flatten.uniq
    if file_ids.empty?
      return render_attach_error("폴더가 비어있거나 접근 권한이 없습니다.")
    end

    attached = 0
    errors = []
    file_ids.each do |fid|
      dl_url = "https://drive.google.com/uc?export=download&confirm=t&id=#{fid}"
      begin
        res = fetch_url_with_redirect(dl_url)
        ct = res["Content-Type"]&.split(";")&.first || "application/octet-stream"
        # confirm 페이지 대응
        if ct.include?("text/html") && res.body.include?("download_warning")
          token = res.body.match(/confirm=([^&"]+)/)[1] rescue "t"
          res = fetch_url_with_redirect("https://drive.google.com/uc?export=download&confirm=#{token}&id=#{fid}")
          ct = res["Content-Type"]&.split(";")&.first || "application/octet-stream"
        end
        next if ct.include?("text/html") # 여전히 HTML이면 skip

        fn = nil
        if res["Content-Disposition"]
          m = res["Content-Disposition"].match(/filename[*]?=(?:UTF-8''|"?)([^";]+)/i)
          fn = m[1].strip if m
        end
        fn ||= "gdrive_#{fid[0..7]}"
        fn = URI.decode_www_form_component(fn) rescue fn

        @order.attachments.attach(io: StringIO.new(res.body), filename: fn, content_type: ct)
        attached += 1
      rescue => e
        errors << "#{fid}: #{e.message}"
      end
    end

    Activity.create!(order: @order, user: current_user, action: "attachment_added") if attached > 0

    msg = "Google Drive 폴더에서 #{attached}개 파일 첨부 완료"
    msg += " (#{errors.size}건 실패)" if errors.any?

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          "drawer-panel-#{@order.id}-attachments",
          partial: "orders/drawer_attachments", locals: { order: @order.reload, initial_render: false, flash_error: errors.any? ? msg : nil }
        )
      }
      format.json { render json: { success: true, attached: attached, errors: errors } }
      format.html { redirect_back fallback_location: @order, notice: msg }
    end
  end

  # Google Drive 파일 ID 추출 (다양한 URL 패턴 대응)
  def extract_gdrive_file_id(url)
    patterns = [
      %r{drive\.google\.com/file/d/([a-zA-Z0-9_-]+)},          # /file/d/ID/view
      %r{drive\.google\.com/open\?id=([a-zA-Z0-9_-]+)},        # /open?id=ID
      %r{docs\.google\.com/document/d/([a-zA-Z0-9_-]+)},       # Docs
      %r{docs\.google\.com/spreadsheets/d/([a-zA-Z0-9_-]+)},   # Sheets
      %r{docs\.google\.com/presentation/d/([a-zA-Z0-9_-]+)},   # Slides
      %r{drive\.google\.com/uc\?.*id=([a-zA-Z0-9_-]+)}         # direct download
    ]
    patterns.each { |p| return $1 if url.match?(p) && url.match(p) }
    nil
  end

  def fetch_url_with_redirect(url, limit = 5)
    raise "URL 리다이렉트 초과" if limit == 0
    uri = URI.parse(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 30) do |http|
      http.get(uri.request_uri, { "User-Agent" => "CPOFlow/1.0" })
    end
    if response.is_a?(Net::HTTPRedirection) && response["location"]
      fetch_url_with_redirect(response["location"], limit - 1)
    else
      response
    end
  end

  def sync_thread_siblings_status(new_status)
    siblings = find_thread_siblings
    return 0 if siblings.empty?

    siblings.find_each do |sibling|
      old = sibling.status
      sibling.update!(status: new_status)
      Activity.create!(
        order: sibling,
        user: current_user,
        action: "status_changed",
        from_status: Order.statuses[old],
        to_status: Order.statuses[sibling.status]
      )
    end

    siblings.count
  end

  # gmail_thread_id 또는 제목의 이벤트 번호로 연관 inbox 건 탐색
  def find_thread_siblings
    base = Order.where(status: :new_rfq).where.not(id: @order.id)

    # 1순위: 동일 gmail_thread_id
    by_thread = base.where(gmail_thread_id: @order.gmail_thread_id) if @order.gmail_thread_id.present?
    return by_thread if by_thread.present? && by_thread.exists?

    # 2순위: 제목에서 숫자 이벤트 번호 추출 후 LIKE 검색
    event_number = @order.original_email_subject&.match(/\b(\d{8,})\b/)&.captures&.first
    return Order.none if event_number.blank?

    base.where("original_email_subject LIKE ?", "%#{event_number}%")
  end

  def order_params
    # 빈 문자열 → nil 정규화 (자동 배정으로 되돌리기 링크)
    if params.dig(:order, :card_status_manually_set_at) == ""
      params[:order][:card_status_manually_set_at] = nil
    end
    params.require(:order).permit(
      :title, :customer_name, :description, :status,
      :card_status_id, :card_status_manually_set_at,
      :due_date, :item_name, :quantity, :currency, :estimated_value,
      :tags, :source_email_id, :original_email_subject,
      :original_email_body, :original_email_from,
      :client_id, :supplier_id, :project_id,
      :rfq_no, :quo_no, :po_no, :kanban_board_id, :kanban_column_id
    )
  end
end
