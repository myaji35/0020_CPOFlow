# frozen_string_literal: true

module Admin
  # Phase E: RFQ AI 학습 통계 API
  # GET /admin/rfq_stats           → HTML 대시보드
  # GET /admin/rfq_stats.json      → JSON API (정확도/일치율/평균 score)
  class RfqStatsController < ApplicationController
    before_action :require_manager!

    def index
      window = params[:window].presence&.to_i || 7
      window = 7 if window <= 0 || window > 365
      @stats = Gmail::RfqFeedbackService.accuracy_stats(window_days: window)

      respond_to do |format|
        format.html
        format.json { render json: @stats }
      end
    end
  end
end
