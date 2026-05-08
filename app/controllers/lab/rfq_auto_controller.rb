# frozen_string_literal: true

# LAB / RFQ Auto — Order 첨부 자동 분석 실험실. admin/manager 전용.
# Phase 1: 목록(new_rfq 카드) + 상세(5단계 분석 결과 + 메트릭).
# 분석은 동기 실행 (Phase 2에서 ActiveJob + Turbo Stream 진행률 스트리밍 도입).
class Lab::RfqAutoController < ApplicationController
  before_action :require_admin_or_manager!
  before_action :load_order, only: %i[show analyze apply feedback]

  # GET /lab/rfq_auto — new_rfq 카드 목록 (분석 안 한 것 우선)
  def index
    base = scoped_orders.where(status: :new_rfq)
                        .includes(:user, :assignees, :client, attachments_attachments: :blob)
                        .order("orders.created_at DESC")
    base = base.where("title LIKE :q OR reference_no LIKE :q OR customer_name LIKE :q",
                      q: "%#{params[:q]}%") if params[:q].present?
    @orders = base.limit(50)

    # 각 Order의 가장 최근 분석 — N+1 방지: 한 번에 SELECT
    order_ids = @orders.map(&:id)
    @latest_analysis_by_order = RfqAutoAnalysis.where(order_id: order_ids)
                                               .order("rfq_auto_analyses.id DESC")
                                               .group_by(&:order_id)
                                               .transform_values(&:first)
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

  def require_admin_or_manager!
    return if current_user&.admin? || current_user&.manager?
    redirect_to root_path, alert: "LAB은 admin/manager 전용입니다."
  end

  def load_order
    @order = scoped_orders.find(params[:id])
  end
end
