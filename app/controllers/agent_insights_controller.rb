# frozen_string_literal: true

class AgentInsightsController < ApplicationController
  # ISS-223: 전체 인사이트 타임라인
  # filter: active(default) / dismissed / all / useful / not_useful
  # type: insight_type 필터
  def index
    @current_filter = params[:filter].presence_in(%w[active dismissed all useful not_useful]) || "active"
    @current_type   = params[:type].presence

    base = AgentInsight.includes(:order, :supplier).order(created_at: :desc)
    scoped = case @current_filter
    when "active"     then base.where(dismissed: false).where("expires_at IS NULL OR expires_at > ?", Time.current)
    when "dismissed"  then base.where(dismissed: true)
    when "useful"     then base.where(useful: true)
    when "not_useful" then base.where(useful: false)
    else                   base
    end
    scoped = scoped.where(insight_type: @current_type) if @current_type.present?
    @insights = scoped.limit(200)

    @total_counts = {
      active:     AgentInsight.where(dismissed: false).where("expires_at IS NULL OR expires_at > ?", Time.current).count,
      dismissed:  AgentInsight.where(dismissed: true).count,
      all:        AgentInsight.count,
      useful:     AgentInsight.where(useful: true).count,
      not_useful: AgentInsight.where(useful: false).count
    }
    @by_type = AgentInsight.group(:insight_type).count.sort_by { |_, c| -c }
    @by_severity = AgentInsight.group(:severity).count
  end

  def dismiss
    insight = AgentInsight.find(params[:id])
    insight.update!(dismissed: true)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("agent-insight-#{insight.id}")
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def feedback
    insight = AgentInsight.find(params[:id])
    useful = params[:useful] == "true"
    insight.update!(useful: useful)

    # Trust Level 업데이트
    level = AgentTrustLevel.record_feedback!(
      user: current_user,
      insight_type: insight.insight_type,
      useful: useful
    )

    respond_to do |format|
      format.turbo_stream do
        streams = [
          turbo_stream.replace(
            "agent-insight-#{insight.id}",
            partial: "agent_insights/insight",
            locals: { insight: insight }
          )
        ]

        # 자동 모드 최초 전환 시 알림
        if level.auto_mode && level.useful_count == AgentTrustLevel::TRUST_THRESHOLD
          streams << turbo_stream.prepend("flash-messages",
            "<div class='mb-4 rounded-lg bg-indigo-50 border border-indigo-200 px-4 py-3 text-indigo-800 text-sm'>이제부터 '#{insight.insight_type}' 유형은 CPO Agent가 자동 처리합니다</div>".html_safe)
        end

        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
