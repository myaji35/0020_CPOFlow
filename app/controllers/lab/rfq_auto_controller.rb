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

  # POST /lab/rfq_auto/:id/analyze
  def analyze
    analysis = RfqAutoAnalysis.create!(
      order:      @order,
      user:       current_user,
      status:     "running",
      llm_model:  ENV.fetch("RFQ_LLM_MODEL", "claude-haiku-4-5-20251001"),
      started_at: Time.current
    )
    RfqAuto::Analyzer.new(analysis).call
    redirect_to lab_rfq_auto_path(@order), notice: analysis.completed? ? "자동 분석 완료" : "자동 분석 실패 — 결과 확인"
  end

  # POST /lab/rfq_auto/:id/apply — Phase 2+: 결과를 Order/Task에 반영
  def apply
    redirect_to lab_rfq_auto_path(@order),
                alert: "Phase 2 — 적용 기능 준비 중. 현재 LAB 결과만 검토 가능."
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

  def require_admin_or_manager!
    return if current_user&.admin? || current_user&.manager?
    redirect_to root_path, alert: "LAB은 admin/manager 전용입니다."
  end

  def load_order
    @order = scoped_orders.find(params[:id])
  end
end
