class InboxController < ApplicationController
  # Rate limiting: AI API 호출은 사용자당 분당 최대 10회
  RATE_LIMIT_WINDOW = 60   # 초
  RATE_LIMIT_MAX    = 10   # 최대 호출 수

  # ISS-261: viewer read-only — 쓰기/변경성 AJAX 액션은 member 이상만
  before_action :require_member!, only: %i[translate analyze_link generate_reply
                                           convert_to_order feedback reclassify
                                           bulk_delete bulk_trash bulk_to_kanban
                                           bulk_all_uncertain_to_kanban bulk_restore
                                           sync destroy]
  # ISS-380: MenuPermission DB 2차 가드
  #  - :create  — 새 칸반 카드 진입 (convert_to_order / bulk_to_kanban / bulk_all_uncertain_to_kanban)
  #  - :update  — AI/번역/피드백/재판독/복원/동기화 (메타데이터 갱신)
  #  - :delete  — 휴지통/일괄삭제/단건삭제
  before_action -> { enforce_menu_permission!(:inbox, :create) },
                only: %i[convert_to_order bulk_to_kanban bulk_all_uncertain_to_kanban]
  before_action -> { enforce_menu_permission!(:inbox, :update) },
                only: %i[translate analyze_link generate_reply feedback reclassify bulk_restore sync]
  before_action -> { enforce_menu_permission!(:inbox, :delete) },
                only: %i[bulk_delete bulk_trash destroy]
  before_action :check_rate_limit!, only: %i[translate analyze_link generate_reply]

  PER_PAGE = 30
  PREFETCH_PAGES = 2  # 1페이지 렌더 후 브라우저가 백그라운드 warm-up 할 페이지 수 (2~3페이지). SQLite 락 리스크 최소화.

  def index
    perf_t0 = Time.now
    @prefetch_mode = params[:frame] == "prefetch"  # lazy turbo-frame prefetch 요청 여부

    # ISS-046 최적화: 목록에서 attachments/blob 미표시 → eager load 제거 (v1 대비 -60%)
    # project도 목록 표시 무관 → 제거. 필요 시 상세 패널에서 개별 로드.
    base_scope = scoped_orders.not_archived
                      .where.not(original_email_from: [ nil, "" ])
                      .includes(:user, :assignees, :client, :supplier)

    # Filter support: all (default), rfq (inbox only), converted (non-inbox), unread (ISS-202)
    @current_filter = params[:filter].presence || "all"
    case @current_filter
    when "rfq"
      base_scope = base_scope.where(status: :new_rfq)
    when "uncertain"
      base_scope = base_scope.where(status: :new_rfq, rfq_status: Order.rfq_statuses[:rfq_pending])
    when "converted"
      base_scope = base_scope.where.not(status: :new_rfq)
    when "unread"
      base_scope = base_scope.where(status: :new_rfq, viewed_at: nil)
    end

    # Search support
    # - 검색 범위: reference_no(인덱스), subject, from, customer_name, title
    # - original_email_body는 풀스캔·느림 → 기본 제외 (?include_body=1로 옵션 복원)
    # - 순수 숫자 쿼리(RFQ 번호 추정): reference_no 부분일치 우선
    @search_query = params[:q].to_s.strip
    if @search_query.present?
      search_term  = "%#{@search_query}%"
      include_body = params[:include_body].to_s == "1"

      if @search_query.match?(/\A[0-9\-]{3,}\z/)
        base_scope = base_scope.where(
          "reference_no LIKE :q OR original_email_subject LIKE :q",
          q: search_term
        )
      else
        conditions = [
          "reference_no LIKE :q",
          "original_email_subject LIKE :q",
          "original_email_from LIKE :q",
          "customer_name LIKE :q",
          "title LIKE :q"
        ]
        conditions << "original_email_body LIKE :q" if include_body
        base_scope = base_scope.where(conditions.join(" OR "), q: search_term)
      end
    end

    # Pagination: 30건씩 로드 (UAE 느린 네트워크 대응)
    @page = [ params[:page].to_i, 1 ].max
    @total_filtered = base_scope.count
    # ambiguous column 차단: includes(:user/:client/:supplier) 가 JOIN으로 승격될 때
    # 모든 테이블이 created_at 보유 → 테이블명 명시 필수.
    @all_orders = base_scope.order(Arel.sql("COALESCE(orders.email_received_at, orders.created_at) DESC"))
                            .offset((@page - 1) * PER_PAGE)
                            .limit(PER_PAGE)
    @total_pages = (@total_filtered.to_f / PER_PAGE).ceil

    # reference_no 기준 그룹핑: 동일 발주번호 메일을 스레드로 묶음
    # key: reference_no (있으면) / "single_{id}" (없으면 단건)
    @grouped_orders = @all_orders
      .group_by { |o| o.reference_no.presence || "single_#{o.id}" }
      .sort_by { |_key, orders| orders.map { |o| o.email_received_at || o.created_at }.max }
      .reverse
      .to_h

    # Counts for sidebar badges — 단일 쿼리로 통합 (4회 → 1회)
    inbox_val     = Order.statuses[:new_rfq].to_i
    uncertain_val = Order.rfq_statuses[:rfq_pending].to_i
    email_scope = scoped_orders.where.not(original_email_from: [ nil, "" ])
    counts = email_scope.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql(ActiveRecord::Base.sanitize_sql([ "SUM(CASE WHEN status = ? THEN 1 ELSE 0 END)", inbox_val ])),
      Arel.sql(ActiveRecord::Base.sanitize_sql([ "SUM(CASE WHEN status = ? AND rfq_status = ? THEN 1 ELSE 0 END)", inbox_val, uncertain_val ])),
      Arel.sql(ActiveRecord::Base.sanitize_sql([ "SUM(CASE WHEN status != ? THEN 1 ELSE 0 END)", inbox_val ])),
      # ISS-202: 읽지 않음 카운트 (viewed_at IS NULL & new_rfq status)
      Arel.sql(ActiveRecord::Base.sanitize_sql([ "SUM(CASE WHEN status = ? AND viewed_at IS NULL THEN 1 ELSE 0 END)", inbox_val ]))
    )
    @count_all, @count_rfq, @count_uncertain, @count_converted, @count_unread = counts.map(&:to_i)

    # 견적성 메일 (rfq_triage) — 우측 패널용
    # ISS-046 후속: 100 → 20건 + prefetch/2페이지에서는 스킵 + count 5분 캐시
    if @prefetch_mode || @page > 1
      @triage_orders = []
      @triage_count = 0
    else
      triage_scope = scoped_orders.where.not(original_email_from: [ nil, "" ])
                                  .where(rfq_status: :rfq_triage)
                                  .includes(:user, :assignees, :client, :supplier)
      @triage_orders = triage_scope.order(created_at: :desc).limit(20)
      @triage_count  = Rails.cache.fetch("inbox:triage_count:#{current_user.id}", expires_in: 5.minutes) do
        triage_scope.count
      end
    end

    # Phase E: 견적성 탭 하단에 표시할 AI 학습 통계 (1페이지에서만 로드, prefetch 시 스킵)
    if @prefetch_mode
      @rfq_ai_stats = nil
    else
      begin
        @rfq_ai_stats = Gmail::RfqFeedbackService.accuracy_stats(window_days: 7)
      rescue => e
        Rails.logger.warn "[Inbox] rfq_ai_stats failed: #{e.class} #{e.message}"
        @rfq_ai_stats = nil
      end
    end

    # [PERF] 성능 측정 로그 — 쿼리 + 총 건수 + 페이지 (ISS-046)
    elapsed_ms = ((Time.now - perf_t0) * 1000).round(1)
    Rails.logger.info "[PERF][inbox] page=#{@page}/#{@total_pages} filter=#{@current_filter} loaded=#{@all_orders.size} total=#{@total_filtered} triage=#{@triage_count || 0} ms=#{elapsed_ms} prefetch=#{@prefetch_mode}"

    # prefetch 모드: 빈 turbo-frame 응답 (DB 쿼리가 이미 실행되어 OS/Rails 쿼리 캐시 warm 상태)
    # → 사용자가 실제 페이지 링크를 클릭하면 ActiveRecord 쿼리 결과가 이미 warm 되어 2~3배 빠름
    if @prefetch_mode
      render html: %(<turbo-frame id="inbox-prefetch-page-#{@page}" data-warmed="true"></turbo-frame>).html_safe,
             layout: false
    end
  end

  def show
    # ISS-254: Branch 격리 — scoped_orders로 현재 사용자 branch 제한
    scope = scoped_orders.includes(attachments_attachments: :blob)
    @order = scope.find_by(source_email_id: params[:id]) || scope.find(params[:id])
    # ISS-202: 읽음 표시 (처음 열람 시만)
    @order.update_column(:viewed_at, Time.current) if @order && @order.viewed_at.nil?
  rescue ActiveRecord::RecordNotFound
    redirect_to inbox_path, alert: "해당 이메일을 찾을 수 없습니다."
  end

  def convert_to_order
    # ISS-254: Branch 격리
    @order = scoped_orders.find(params[:id])

    # Phase F (ISS-034): rfq_status 게이트 — 제외/보관된 메일은 칸반 진입 차단
    unless @order.rfq_convertible?
      redirect_back fallback_location: inbox_path,
                    alert: "제외/보관 처리된 메일은 주문으로 전환할 수 없습니다."
      return
    end

    # ISS-055: 칸반 진입은 항상 new_rfq 칼럼 (status :new_rfq 유지 + rfq_status :rfq_triage)
    board = if params[:board_id].present?
      KanbanBoard.find_by(id: params[:board_id])
    else
      KanbanBoard.default_board.first || KanbanBoard.ensure_default!
    end
    if @order.update(status: :new_rfq, rfq_status: :rfq_triage, kanban_board_id: board.id)
      Activity.create!(order: @order, user: current_user, action: "moved_to_kanban")
      record_bulk_feedback([ @order ], "confirmed")
      redirect_to kanban_path, notice: t("inbox.convert_success")
    else
      redirect_back fallback_location: inbox_path, alert: "Failed to convert."
    end
  end

  # POST /inbox/bulk_trash — 멀티체크 진짜 삭제 (Gmail Trash + archived_at)
  def bulk_trash
    ids = Array(params[:order_ids]).map(&:to_i).uniq
    orders = scoped_orders.where(id: ids).to_a
    accounts = current_user.email_accounts.where(connected: true).to_a

    trashed_count = 0
    orders.each do |order|
      if order.source_email_id.present?
        accounts.each do |acct|
          begin
            if Gmail::GmailService.new(acct).trash_message(order.source_email_id)
              trashed_count += 1
              break
            end
          rescue => e
            Rails.logger.warn "[inbox#bulk_trash] Gmail trash 실패 ord=#{order.id} acct=#{acct.email}: #{e.class} #{e.message}"
          end
        end
      end
      order.archive!
    end

    render json: {
      status: "ok",
      count: orders.size,
      gmail_trashed: trashed_count,
      message: "#{orders.size}건을 휴지통으로 이동 (Gmail 삭제 #{trashed_count}건)"
    }
  end

  # POST /inbox/bulk_delete — [LEGACY] 멀티체크 삭제 (rfq_excluded 마킹만, Gmail 유지)
  def bulk_delete
    orders = scoped_orders.where(id: params[:order_ids], status: :new_rfq)
    count = orders.count
    record_bulk_feedback(orders, "rejected")
    orders.update_all(rfq_status: Order.rfq_statuses[:rfq_excluded])
    render json: { status: "ok", count: count, message: "#{count}건 삭제 처리" }
  end

  # POST /inbox/bulk_to_kanban — 멀티체크 견적 이동 (칸반 New)
  def bulk_to_kanban
    # Phase F (ISS-034): rfq_status 게이트 — excluded/archived 제외
    eligible_statuses = Order.rfq_statuses.values_at("rfq_triage", "rfq_pending")
    orders = scoped_orders.where(id: params[:order_ids], status: :new_rfq, rfq_status: eligible_statuses)
    blocked_count = Array(params[:order_ids]).size - orders.count
    count = orders.count
    record_bulk_feedback(orders, "confirmed")
    board = if params[:board_id].present?
      KanbanBoard.find_by(id: params[:board_id])
    else
      KanbanBoard.default_board.first || KanbanBoard.ensure_default!
    end
    orders.each do |order|
      # ISS-055: 칸반 진입은 항상 new_rfq 칼럼
      order.update!(status: :new_rfq, rfq_status: :rfq_triage, kanban_board_id: board.id)
      Activity.create!(order: order, user: current_user, action: "moved_to_kanban")
    end
    message = "#{count}건 견적으로 이동"
    message += " (#{blocked_count}건은 제외/보관 상태로 차단됨)" if blocked_count.positive?
    render json: { status: "ok", count: count, blocked: blocked_count, message: message }
  end

  # POST /inbox/bulk_all_uncertain_to_kanban
  # 현재 필터/검색에 매치되는 rfq_pending 전건을 한 번에 칸반 진입.
  # rfq_pending 누적(운영 4,582건) 일괄 해소용 — confirm_token 으로 안전장치.
  def bulk_all_uncertain_to_kanban
    # 안전장치: confirm_token 확인 (UI 가 "OK" 입력 후 hidden 값으로 전송)
    return render json: { error: "확인 토큰 누락 — UI 사용 권장" }, status: :unprocessable_entity unless params[:confirm_token] == "PROCEED"

    target_filter = params[:filter].presence || "uncertain"
    search_query  = params[:q].to_s.strip
    max_batch     = [ params[:max].to_i, 0 ].max
    max_batch     = 5000 if max_batch.zero? || max_batch > 5000  # 안전상한

    base_scope = scoped_orders.not_archived
                              .where.not(original_email_from: [ nil, "" ])
                              .where(status: :new_rfq, rfq_status: :rfq_pending)

    case target_filter
    when "uncertain"
      # 그대로 사용
    when "rfq", "all"
      # rfq/all 필터에서도 동작 — rfq_pending 만 잡음
    else
      return render json: { error: "지원하지 않는 필터" }, status: :unprocessable_entity
    end

    if search_query.present?
      term = "%#{search_query}%"
      base_scope = base_scope.where(
        "reference_no LIKE :q OR original_email_subject LIKE :q OR original_email_from LIKE :q OR customer_name LIKE :q OR title LIKE :q",
        q: term
      )
    end

    target_orders = base_scope.limit(max_batch).to_a
    count = target_orders.size

    if count.zero?
      return render json: { status: "ok", count: 0, message: "처리할 미분류 카드가 없습니다." }
    end

    board = if params[:board_id].present?
      KanbanBoard.find_by(id: params[:board_id])
    else
      KanbanBoard.default_board.first || KanbanBoard.ensure_default!
    end

    # 일괄 update — 학습 데이터 누적 + Activity 기록 (callback 트리거 필요하므로 each)
    record_bulk_feedback(target_orders, "confirmed")
    target_orders.each_slice(500) do |batch|
      batch.each do |order|
        order.update!(status: :new_rfq, rfq_status: :rfq_triage, kanban_board_id: board.id)
        Activity.create!(order: order, user: current_user, action: "bulk_uncertain_to_kanban")
      end
    end

    Rails.logger.info "[inbox#bulk_all_uncertain] #{count}건 일괄 칸반 진입 (filter=#{target_filter} q=#{search_query.presence || '-'} board=#{board.id})"
    render json: {
      status:  "ok",
      count:   count,
      filter:  target_filter,
      board:   board.name,
      message: "#{count}건을 칸반 New 컬럼으로 일괄 이동했습니다."
    }
  end

  # POST /inbox/bulk_restore — 휴지통 복원 (rfq_pending)
  def bulk_restore
    orders = scoped_orders.where(id: params[:order_ids], rfq_status: :rfq_excluded)
    count = orders.count
    record_bulk_feedback(orders, "reverted")
    orders.update_all(rfq_status: Order.rfq_statuses[:rfq_pending])
    render json: { status: "ok", count: count, message: "#{count}건 복원" }
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
    # ISS-254: Branch 격리
    order = scoped_orders.find(params[:id])
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
  rescue => e
    if e.message.to_s.match?(/credit|quota|limit|insufficient|exceeded|401|402|429/i)
      render json: { error: "API 크레딧 부족. keyword 기반 분석으로 전환됩니다.", api_exhausted: true }, status: :service_unavailable
    else
      render json: { error: "번역 중 오류: #{e.message.truncate(100)}" }, status: :internal_server_error
    end
  end

  # ISS-213: AI 재판독 트리거
  # 원본 이메일 필드로 parsed hash 재구성 → ClassificationOrchestrator 재실행
  # 결과: rfq_status 업데이트 + rfq_feedback 로그에 "reclassified" 기록
  def reclassify
    # ISS-254: Branch 격리
    order = scoped_orders.find(params[:id])

    unless order.original_email_from.present? && order.original_email_subject.present?
      return render json: { error: "원본 이메일 데이터가 없어 재판독 불가" }, status: :unprocessable_entity
    end

    parsed = {
      id:        order.source_email_id || "reclassify-#{order.id}",
      thread_id: order.gmail_thread_id.to_s,
      subject:   order.original_email_subject.to_s,
      from:      order.original_email_from.to_s,
      to:        "",
      date:      order.email_received_at,
      snippet:   order.original_email_body.to_s.truncate(200),
      body:      order.original_email_body.to_s,
      html_body: order.original_email_html_body.to_s,
      labels:    [],
      unread:    false
    }

    prev_rfq_status = order.rfq_status

    result = Gmail::ClassificationOrchestrator.new(parsed, order: order).classify

    # verdict → rfq_status 매핑 (기존 orchestrator 규칙 따름)
    new_rfq_status = case result.verdict.to_sym
    when :confirmed then :rfq_triage
    when :excluded  then :rfq_excluded
    else                 :rfq_pending
    end

    order.update!(rfq_status: new_rfq_status)
    Gmail::RfqFeedbackService.record!(order, current_user,
                                      verdict: "reclassified",
                                      note: "v=#{result.classifier_version} s=#{result.stage_reached} conf=#{result.confidence} prev=#{prev_rfq_status}") rescue nil

    render json: {
      status: "ok",
      prev_rfq_status: prev_rfq_status,
      new_rfq_status: order.reload.rfq_status,
      verdict: result.verdict,
      confidence: result.confidence,
      stage_reached: result.stage_reached,
      classifier_version: result.classifier_version,
      reason: result.reason,
      message: "재판독 완료: #{prev_rfq_status} → #{order.rfq_status}"
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  rescue => e
    Rails.logger.error "[inbox#reclassify] #{e.class}: #{e.message}"
    render json: { error: "재판독 실패: #{e.message.truncate(150)}" }, status: :internal_server_error
  end

  # AJAX: 사용자 RFQ 피드백 (맞음/아님)
  def feedback
    # ISS-254: Branch 격리
    order = scoped_orders.find(params[:id])
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
    # ISS-254: Branch 격리
    order = scoped_orders.find(params[:id])
    order.update_column(:reply_draft, nil)  # 기존 초안 삭제 후 재생성
    draft = Gmail::RfqReplyDraftService.generate!(order)

    if draft.present?
      render json: { status: "ok", draft: draft }
    else
      render json: { error: "답변 초안 생성에 실패했습니다." }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "not found" }, status: :not_found
  rescue Faraday::ClientError, Faraday::ServerError, Net::HTTPClientException => e
    if e.message.to_s.match?(/401|402|403|429|quota|credit|limit|insufficient/i)
      render json: { error: "API 크레딧 부족. keyword 기반 분석으로 전환됩니다.", api_exhausted: true }, status: :service_unavailable
    else
      render json: { error: "AI 서비스 오류: #{e.message.truncate(100)}" }, status: :service_unavailable
    end
  rescue => e
    if e.message.to_s.match?(/credit|quota|limit|insufficient|exceeded/i)
      render json: { error: "API 크레딧 부족. keyword 기반 분석으로 전환됩니다.", api_exhausted: true }, status: :service_unavailable
    else
      render json: { error: "답변 초안 생성 중 오류: #{e.message.truncate(100)}" }, status: :internal_server_error
    end
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

  # DELETE /inbox/:id — 받은편지함에서 제거 (Gmail Trash 이동 + CPOFlow archived)
  def destroy
    order = scoped_orders.find(params[:id])

    gmail_trashed = false
    if order.source_email_id.present?
      current_user.email_accounts.where(connected: true).find_each do |acct|
        begin
          if Gmail::GmailService.new(acct).trash_message(order.source_email_id)
            gmail_trashed = true
            break
          end
        rescue => e
          Rails.logger.warn "[inbox#destroy] Gmail trash 실패 ord=#{order.id} acct=#{acct.email}: #{e.class} #{e.message}"
        end
      end
    end

    order.archive!

    notice = gmail_trashed ? "메일을 휴지통으로 이동했습니다 (Gmail·Inbox 동시)" : "Inbox에서 숨김 처리했습니다 (Gmail 삭제 실패 — 권한·토큰 확인 필요)"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("email-item-#{order.id}"),
          turbo_stream.remove("email-detail-#{order.id}")
        ]
      end
      format.html { redirect_to inbox_path, notice: notice }
    end
  end

  private

  # Bulk 액션 시 RfqFeedback 일괄 기록 (정답 데이터 축적)
  def record_bulk_feedback(orders, verdict)
    orders.each do |order|
      Gmail::RfqFeedbackService.record!(order, current_user, verdict: verdict, note: "bulk_action")
    end
  end

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
      last_row  = [ spreadsheet.last_row || 0, 500 ].min  # 최대 500행
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
          document.addEventListener('keydown', function(e) { if (e.key === 'Escape') window.parent.postMessage('close-preview-modal', '*'); });
        </script>
      </body></html>
    HTML
  end

  public

  # 첨부파일 미리보기 (xlsx/xls → HTML 테이블 변환, 기타 → inline redirect)
  def preview_attachment
    # ISS-062 권한 가드 복원: scoped_orders로 사용자 접근 가능 주문만, blob은 해당 order 첨부에서만
    order = scoped_orders.includes(attachments_attachments: :blob).find(params[:id])
    attachment = order.attachments.find { |a| a.blob_id.to_s == params[:blob_id].to_s }
    return render(html: "<p style='padding:2rem;color:#c00;'>권한 없음</p>".html_safe, layout: false, status: :forbidden) unless attachment
    blob = attachment.blob

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
        raw = File.read(tempfile.path)
        # 인코딩 안전화: UTF-8 강제 + invalid 바이트는 치환 (Ariba HTML 스크랩 등 깨진 인코딩 방어)
        html_content = raw.force_encoding("UTF-8")
        unless html_content.valid_encoding?
          html_content = raw.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "")
        end
        # 상대경로 링크 차단: base href를 about:blank로 설정하여 iframe 내 링크 클릭이 메인창을 이동시키지 않음
        base_tag = '<base href="about:blank" target="_blank">'
        if html_content.include?("<head>")
          html_content = html_content.sub("<head>", "<head>#{base_tag}")
        elsif html_content.include?("<html")
          html_content = html_content.sub(/<html[^>]*>/i) { |m| "#{m}<head>#{base_tag}</head>" }
        else
          html_content = "#{base_tag}#{html_content}"
        end
        # iframe 내 ESC 키 → 부모 모달 닫기 (</body> 없으면 끝에 덧붙임)
        esc_script = '<script>document.addEventListener("keydown",function(e){if(e.key==="Escape")window.parent.postMessage("close-preview-modal","*")});</script>'
        html_content = if html_content.include?("</body>")
          html_content.sub("</body>", "#{esc_script}</body>")
        else
          html_content + esc_script
        end
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
    # ISS-062 권한 가드 복원: scoped_orders로 사용자 접근 가능 주문만
    order = scoped_orders.includes(attachments_attachments: :blob).find(params[:id])
    blob_key = params[:blob_key]

    attachment = order.attachments.find { |a| a.blob.key == blob_key }
    if attachment
      redirect_to rails_blob_path(attachment.blob, disposition: "attachment"), allow_other_host: false
    else
      render json: { error: "첨부파일을 찾을 수 없습니다" }, status: :not_found
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "권한 없음 또는 not found" }, status: :forbidden
  end
end
