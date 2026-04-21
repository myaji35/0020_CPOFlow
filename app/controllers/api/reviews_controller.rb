# frozen_string_literal: true

module Api
  class ReviewsController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :verify_authenticity_token
    before_action :require_api_key!

    # GET /api/reviews
    # Command Center(0000_master) 등 외부 시스템 폴링용.
    # 인증: X-CPOFlow-API-Key 헤더 또는 ?api_key= 파라미터.
    # email 원문은 절대 포함되지 않음 (email_hash만).
    def index
      reviews = Review.order(created_at: :desc).limit(50)
      render json: {
        total: reviews.size,
        reviews: reviews.map(&:to_review_json)
      }
    end

    private

    def require_api_key!
      provided = request.headers["X-CPOFlow-API-Key"].presence || params[:api_key].presence
      expected = resolved_api_key
      if expected.blank?
        render json: { error: "API key not configured on server" }, status: :service_unavailable
        return
      end
      unless provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected.to_s)
        render json: { error: "Invalid or missing API key" }, status: :unauthorized
      end
    end

    # 우선순위: ENV > credentials
    def resolved_api_key
      ENV["CPOFLOW_API_KEY"].presence ||
        (Rails.application.credentials.dig(:cpoflow, :api_key) rescue nil)
    end
  end
end
