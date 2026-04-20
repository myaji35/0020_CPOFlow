# frozen_string_literal: true

module Api
  class ReviewsController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :verify_authenticity_token

    # GET /api/reviews
    def index
      reviews = Review.order(created_at: :desc).limit(50)
      render json: {
        total: reviews.size,
        reviews: reviews.map(&:to_review_json)
      }
    end
  end
end
