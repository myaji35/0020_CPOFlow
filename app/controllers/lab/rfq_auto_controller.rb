# frozen_string_literal: true

# LAB / RFQ Auto — Order 첨부 자동 분석 실험실. admin/manager 전용.
# Phase 1: 목록(new_rfq 카드) + 상세(5단계 분석 결과 + 메트릭).
# 분석은 동기 실행 (Phase 2에서 ActiveJob + Turbo Stream 진행률 스트리밍 도입).
class Lab::RfqAutoController < ApplicationController
  before_action :require_admin_or_manager!
  before_action :load_order, only: %i[show analyze apply feedback upload destroy_attachment select_supplier send_rfq_emails]

  # GET /lab/rfq_auto — new_rfq 카드 + 샌드박스 카드 목록
  def index
    base = lab_scoped_orders.where("orders.status = ? OR orders.lab_sandbox = ?",
                                   Order.statuses[:new_rfq], true)
                            .includes(:user, :assignees, :client, attachments_attachments: :blob)
                            .order("orders.lab_sandbox DESC, orders.created_at DESC")
    base = base.where("orders.title LIKE :q OR orders.reference_no LIKE :q OR orders.customer_name LIKE :q",
                      q: "%#{params[:q]}%") if params[:q].present?
    @orders = base.limit(80)

    order_ids = @orders.map(&:id)
    @latest_analysis_by_order = RfqAutoAnalysis.where(order_id: order_ids)
                                               .order("rfq_auto_analyses.id DESC")
                                               .group_by(&:order_id)
                                               .transform_values(&:first)
  end

  # POST /lab/rfq_auto/sandbox — 빈 샌드박스 Order 생성 → show로 이동
  def sandbox
    order = Order.new(
      title:           "[LAB Sandbox] #{Time.current.strftime('%Y-%m-%d %H:%M')}",
      status:          :new_rfq,
      rfq_status:      :rfq_pending,
      lab_sandbox:     true,
      user_id:         current_user.id,
      customer_name:   "LAB Sandbox",
      reference_no:    "LAB-#{Time.current.to_i.to_s(36)}"
    )
    # 일부 검증 면제 — sandbox는 운영 영역에서 안 보이므로 필수값 우회
    if order.save(validate: false)
      redirect_to lab_rfq_auto_path(order), notice: "샌드박스 카드 생성 — 임의 첨부파일을 업로드해 분석을 시도해보세요."
    else
      redirect_to lab_rfq_auto_index_path, alert: "샌드박스 생성 실패: #{order.errors.full_messages.join(', ')}"
    end
  end

  # GET /lab/rfq_auto/:id
  def show
    @analyses = @order.rfq_auto_analyses.recent.includes(:user).limit(10)
    @latest   = @analyses.first
  end

  # POST /lab/rfq_auto/:id/analyze — 비동기 실행, Turbo Stream으로 진행률 갱신
  def analyze
    analysis = RfqAutoAnalysis.create!(
      order:      @order,
      user:       current_user,
      status:     "running",
      llm_model:  ENV.fetch("RFQ_LLM_MODEL", "claude-haiku-4-5-20251001"),
      started_at: Time.current
    )
    RfqAutoAnalyzeJob.perform_later(analysis.id)
    redirect_to lab_rfq_auto_path(@order), notice: "자동 분석을 시작했습니다 — 결과는 자동으로 갱신됩니다."
  end

  # POST /lab/rfq_auto/:id/apply?analysis_id=N
  # LAB 분석 결과를 실제 Order에 반영 — 품목 누락 항목을 Task로 자동 생성.
  # 안전장치: completed 상태만 적용 가능 + 이미 적용된 분석은 거부 (중복 Task 차단).
  def apply
    analysis = @order.rfq_auto_analyses.find(params[:analysis_id])
    unless analysis.completed?
      return redirect_to lab_rfq_auto_path(@order), alert: "완료된 분석만 적용 가능합니다 (status=#{analysis.status})."
    end
    if analysis.summary_data["applied_at"].present?
      return redirect_to lab_rfq_auto_path(@order), alert: "이미 적용된 분석입니다."
    end

    created = apply_analysis_to_order!(analysis)

    redirect_to lab_rfq_auto_path(@order),
                notice: "적용 완료 — Task #{created[:tasks]}건 자동 생성"
  rescue ActiveRecord::RecordNotFound
    redirect_to lab_rfq_auto_path(@order), alert: "분석 기록을 찾을 수 없습니다."
  rescue StandardError => e
    Rails.logger.error "[Lab::RfqAuto#apply] #{e.class}: #{e.message}"
    redirect_to lab_rfq_auto_path(@order), alert: "적용 중 오류: #{e.message}"
  end

  # POST /lab/rfq_auto/:id/upload — 임의 첨부파일 업로드 (단일/복수)
  # params[:files] = 파일 배열, params[:auto_analyze] = "1"이면 업로드 직후 분석 트리거
  def upload
    files = Array(params[:files]).reject(&:blank?)
    if files.empty?
      return redirect_to lab_rfq_auto_path(@order), alert: "파일을 선택해주세요."
    end

    attached = 0
    files.each do |f|
      next unless f.respond_to?(:original_filename)
      @order.attachments.attach(io: f.tempfile, filename: f.original_filename, content_type: f.content_type)
      attached += 1
    end

    if params[:auto_analyze] == "1"
      analysis = RfqAutoAnalysis.create!(
        order: @order, user: current_user, status: "running",
        llm_model: ENV.fetch("RFQ_LLM_MODEL", "claude-haiku-4-5-20251001"),
        started_at: Time.current
      )
      RfqAutoAnalyzeJob.perform_later(analysis.id)
      redirect_to lab_rfq_auto_path(@order), notice: "#{attached}개 파일 업로드 + 자동 분석 시작."
    else
      redirect_to lab_rfq_auto_path(@order), notice: "#{attached}개 파일 업로드 완료. '🔬 자동 분석 시작' 버튼으로 분석하세요."
    end
  rescue StandardError => e
    Rails.logger.error "[Lab::RfqAuto#upload] #{e.class}: #{e.message}"
    redirect_to lab_rfq_auto_path(@order), alert: "업로드 실패: #{e.message}"
  end

  # DELETE /lab/rfq_auto/:id/attachments/:attachment_id — 첨부 1건 삭제
  def destroy_attachment
    att = @order.attachments_attachments.find(params[:attachment_id])
    att.purge_later
    redirect_to lab_rfq_auto_path(@order), notice: "첨부 1건 삭제 요청."
  rescue ActiveRecord::RecordNotFound
    redirect_to lab_rfq_auto_path(@order), alert: "첨부를 찾을 수 없습니다."
  end

  # POST /lab/rfq_auto/:id/select_supplier — D-5 공급사 선택/해제 (토글)
  # params: analysis_id, item_idx, supplier_name, contact_email, website, country, source, confidence, supplier_id?
  def select_supplier
    analysis = @order.rfq_auto_analyses.find(params[:analysis_id])
    item_idx = params[:item_idx].to_i
    sup_name = params[:supplier_name].to_s.strip
    return redirect_to lab_rfq_auto_path(@order), alert: "공급사 정보 부족" if sup_name.blank? || item_idx.zero?

    existing = analysis.supplier_selections.find_by(item_idx: item_idx, supplier_name: sup_name)
    if existing
      existing.destroy
      redirect_to lab_rfq_auto_path(@order), notice: "선택 해제: #{sup_name}"
    else
      analysis.supplier_selections.create!(
        item_idx:           item_idx,
        item_keyword:       params[:item_keyword],
        supplier_name:      sup_name,
        supplier_id:        params[:supplier_id].presence,
        contact_email:      params[:contact_email],
        contact_phone:      params[:contact_phone],
        website:            params[:website],
        country:            params[:country],
        source:             params[:source],
        confidence:         params[:confidence].to_i,
        source_url:         params[:source_url],
        selected_by_user_id: current_user.id
      )
      redirect_to lab_rfq_auto_path(@order), notice: "선택: #{sup_name}"
    end
  end

  # POST /lab/rfq_auto/:id/send_rfq_emails — D-6 선택된 공급사들에게 멀티 이메일
  def send_rfq_emails
    analysis = @order.rfq_auto_analyses.find(params[:analysis_id])
    selections = analysis.supplier_selections.pending_email.where.not(contact_email: [ nil, "" ])
    return redirect_to lab_rfq_auto_path(@order), alert: "이메일 보낼 선택 공급사 없음 (이메일 주소 누락 또는 이미 발송)" if selections.empty?

    items = (analysis.steps_data["step2_items"] || {})["items"] || []
    attachments_data = @order.attachments_attachments.includes(:blob).first(5).map do |att|
      next nil if att.blob.byte_size > 10.megabytes
      { filename: att.blob.filename.to_s, content_type: att.blob.content_type, body: att.blob.download }
    rescue StandardError
      nil
    end.compact

    sent = 0
    failed = []
    selections.each do |sel|
      RfqAutoMailer.with(
        selection:        sel,
        order:            @order,
        items:            items,
        attachments_data: attachments_data,
        from_user:        current_user
      ).rfq_inquiry.deliver_later
      sel.update!(emailed_at: Time.current)
      sent += 1
    rescue StandardError => e
      failed << "#{sel.supplier_name}: #{e.message.truncate(80)}"
    end

    msg = "이메일 발송 큐잉: #{sent}건"
    msg += " · 실패 #{failed.size}건 (#{failed.first(3).join('; ')})" if failed.any?
    redirect_to lab_rfq_auto_path(@order), notice: msg
  end

  # GET/POST /lab/rfq_auto/import_suppliers — D-4 CSV/표 붙여넣기
  # params: text (TSV/CSV with headers: 품목,업체명,이메일,홈페이지[,전화,국가])
  def import_suppliers
    if request.post?
      raw = params[:text].to_s
      return redirect_to import_suppliers_lab_rfq_auto_index_path, alert: "텍스트 비어 있음" if raw.strip.blank?

      rows = parse_tsv_or_csv(raw)
      return redirect_to import_suppliers_lab_rfq_auto_index_path, alert: "헤더 행 인식 실패 (품목/업체명/이메일/홈페이지 필요)" if rows.blank?

      saved = 0
      skipped = 0
      rows.each do |row|
        name = row["업체명"] || row["company"] || row["name"]
        item = row["품목"]   || row["item"]
        next if name.to_s.strip.blank?

        normalized = name.to_s.strip.downcase
        if Supplier.where("LOWER(TRIM(name)) = ?", normalized).exists?
          skipped += 1
          next
        end

        Supplier.create!(
          name:           name.to_s.strip[0, 200],
          contact_email:  (row["이메일"] || row["email"]).to_s[0, 100],
          contact_phone:  (row["전화"]   || row["phone"]).to_s[0, 50],
          website:        (row["홈페이지"] || row["website"]).to_s[0, 250],
          country:        (row["국가"]   || row["country"]).to_s[0, 10],
          auto_imported:  true,
          import_source:  "csv_upload",
          discovered_for: item.to_s[0, 200],
          notes:          "CSV/표 import — by #{current_user.display_name}"
        )
        saved += 1
      end
      redirect_to import_suppliers_lab_rfq_auto_index_path,
                  notice: "import 완료: 신규 #{saved}건 / 중복 skip #{skipped}건"
    else
      @recent_imports = Supplier.where(import_source: "csv_upload").order("suppliers.created_at DESC").limit(20)
    end
  end

  # POST /lab/rfq_auto/:id/feedback?value=correct/wrong/partial
  def feedback
    analysis_id = params[:analysis_id].to_i
    value = params[:value].to_s
    unless RfqAutoAnalysis::FEEDBACKS.include?(value)
      return redirect_to lab_rfq_auto_path(@order), alert: "잘못된 피드백 값"
    end
    analysis = RfqAutoAnalysis.find_by(id: analysis_id, order_id: @order.id)
    return redirect_to lab_rfq_auto_path(@order), alert: "분석 기록 없음" unless analysis
    analysis.update!(feedback: value)
    redirect_to lab_rfq_auto_path(@order), notice: "피드백 저장: #{value}"
  end

  private

  # 분석 결과 → Order Task. 누락 항목 1건당 Task 1개. auto_generated=true.
  # 트랜잭션으로 일괄 처리. summary에 applied_at + tasks_created 기록 → 중복 적용 차단.
  def apply_analysis_to_order!(analysis)
    items_step = analysis.steps_data["step2_items"] || {}
    tasks_step = analysis.steps_data["step3_tasks"] || {}

    items   = items_step["items"].is_a?(Array) ? items_step["items"] : []
    tasks   = tasks_step["tasks"].is_a?(Array) ? tasks_step["tasks"] : []
    created_tasks = 0

    ActiveRecord::Base.transaction do
      tasks.select { |t| t["status"] == "missing" }.each do |t|
        title = "[#{t["item_name"].presence || "품목 #{t["item_idx"]}"}] #{t["label"]} 확인"
        # 같은 title 이미 있으면 skip — 중복 차단
        next if @order.tasks.where(title: title).exists?

        @order.tasks.create!(
          title:          title,
          description:    "RFQ Auto 분석에 의해 자동 생성된 누락 항목 점검 Task. (분석 ID #{analysis.id})",
          completed:      false,
          auto_generated: true
        )
        created_tasks += 1
      end

      summary_payload = analysis.summary_data.merge(
        "applied_at"     => Time.current.iso8601,
        "applied_by"     => current_user.id,
        "tasks_created"  => created_tasks,
        "items_applied"  => items.size
      )
      analysis.update!(summary: summary_payload.to_json)
    end

    { tasks: created_tasks, items: items.size }
  end

  # TSV(탭 구분) 또는 CSV 본문을 hash 배열로. 첫 줄 헤더.
  def parse_tsv_or_csv(text)
    lines = text.split(/\r?\n/).map(&:strip).reject(&:blank?)
    return [] if lines.size < 2
    sep = lines.first.include?("\t") ? "\t" : ","
    headers = lines.shift.split(sep).map(&:strip)
    lines.map do |line|
      vals = line.split(sep).map(&:strip)
      headers.zip(vals).to_h
    end
  end

  def require_admin_or_manager!
    return if current_user&.admin? || current_user&.manager?
    redirect_to root_path, alert: "LAB은 admin/manager 전용입니다."
  end

  def load_order
    @order = lab_scoped_orders.find(params[:id])
  end
end
