# frozen_string_literal: true

module Admin
  class AgentRunsController < ApplicationController
    before_action :require_admin!

    WINDOWS = {
      "24h" => -> { 24.hours.ago },
      "7d" => -> { 7.days.ago },
      "30d" => -> { 30.days.ago }
    }.freeze
    STATUSES = %w[success fallback failure skipped running].freeze

    def index
      @agent_options = AgentRun.distinct.pluck(:agent_name).compact.sort
      @model_options = AgentRun.distinct.pluck(:model).compact.sort
      normalize_filters

      scope = AgentRun.all
      scope = scope.in_window(WINDOWS.fetch(@window).call) unless @window == "all"
      scope = scope.where(agent_name: @agent_filter) if @agent_filter.present?
      scope = scope.where(model: @model_filter) if @model_filter.present?
      scope = scope.where(status: @status_filter) if @status_filter.present?

      @total_runs = scope.count
      @total_cost = scope.sum(:cost_usd)
      @measured_cnt = scope.where.not(cost_usd: nil).count
      status_counts = scope.group(:status).count
      completed_count = @total_runs - status_counts.fetch("running", 0)
      failed_count = status_counts.fetch("failure", 0) + status_counts.fetch("fallback", 0)
      @fail_rate = completed_count.zero? ? nil : failed_count * 100.0 / completed_count
      @avg_duration = scope.average(:duration_ms)
      @by_model = scope.group(:model).count

      raw_agg = scope.group(:agent_name, :model).pluck(
        Arel.sql("agent_name, model, COUNT(*), SUM(cost_usd), AVG(duration_ms), " \
                 "SUM(CASE WHEN status IN ('failure','fallback') THEN 1 ELSE 0 END), MAX(started_at)")
      )
      total_cost = @total_cost.to_d
      @agg = raw_agg.map do |agent_name, model, count, cost, avg_duration, failed, last_run|
        row_cost = cost&.to_d
        {
          agent_name: agent_name,
          model: model,
          count: count,
          cost: row_cost,
          cost_pct: total_cost.positive? && row_cost ? row_cost * 100 / total_cost : 0,
          avg_duration: avg_duration,
          fail_rate: count.zero? ? nil : failed.to_i * 100.0 / count,
          last_run: last_run.is_a?(String) ? Time.zone.parse(last_run) : last_run
        }
      end.sort_by { |row| -(row[:cost] || 0) }

      @runs = scope.includes(:order).order(started_at: :desc).limit(50)
      @cost_guard = Gmail::CostGuard.status rescue nil
    end

    private

    def normalize_filters
      requested_window = params[:window].to_s
      @window = (WINDOWS.keys + [ "all" ]).include?(requested_window) ? requested_window : "all"

      requested_agent = params[:agent].to_s
      @agent_filter = requested_agent if @agent_options.include?(requested_agent)

      requested_model = params[:model].to_s
      @model_filter = requested_model if @model_options.include?(requested_model)

      requested_status = params[:status].to_s
      @status_filter = requested_status if STATUSES.include?(requested_status)
    end
  end
end
