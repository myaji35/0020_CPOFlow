# frozen_string_literal: true

class AgentInsightsController < ApplicationController
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
    insight.update!(useful: params[:useful] == "true")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "agent-insight-#{insight.id}",
          partial: "agent_insights/insight",
          locals: { insight: insight }
        )
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
