# frozen_string_literal: true

module Admin
  class ReviewsController < ApplicationController
    before_action :require_admin!
    before_action :set_review, only: %i[transition]

    VALID_STATUSES = %w[new triaged responded archived].freeze

    # GET /admin/reviews
    def index
      @reviews = Review.order(created_at: :desc)

      if params[:status].present?
        # "new" → "new_review" 매핑
        mapped = params[:status] == "new" ? "new_review" : params[:status]
        @reviews = @reviews.where(status: Review.statuses[mapped])
      end

      @reviews = @reviews.limit(100)
      @status_counts = Review.group(:status).count
    end

    # PATCH /admin/reviews/:id/transition
    def transition
      to = params[:to].to_s
      unless VALID_STATUSES.include?(to)
        redirect_to admin_reviews_path, alert: "잘못된 상태입니다."
        return
      end

      @review.status = to  # 커스텀 세터가 "new" → "new_review" 변환
      if @review.save
        ReviewJsonSyncService.new.update(@review)
        redirect_to admin_reviews_path, notice: "상태가 '#{to}'로 변경되었습니다."
      else
        redirect_to admin_reviews_path, alert: "상태 변경에 실패했습니다."
      end
    end

    private

    def set_review
      @review = Review.find(params[:id])
    end
  end
end
