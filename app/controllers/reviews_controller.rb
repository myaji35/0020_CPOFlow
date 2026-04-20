# frozen_string_literal: true

class ReviewsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[new create]

  # Rate limiting: IP당 1분에 3건 (세션 기반)
  RATE_LIMIT_COUNT = 3
  RATE_LIMIT_WINDOW = 60 # seconds

  # GET /reviews/new
  def new
    @review = Review.new
  end

  # POST /reviews
  def create
    if rate_limited?
      respond_to do |format|
        format.html do
          flash[:alert] = "너무 많은 요청입니다. 잠시 후 다시 시도해주세요."
          render :new, status: :too_many_requests
        end
        format.json { render json: { error: "Rate limit exceeded" }, status: :too_many_requests }
      end
      return
    end

    @review = Review.new(review_params)
    @review.user_agent = request.user_agent
    @review.ip_address = request.remote_ip

    # email 해시 처리
    if params[:hash_email] == "1" && review_params[:email].present?
      @review.email_hash = Digest::SHA256.hexdigest(review_params[:email].strip.downcase)
      @review.email = nil
    end

    if @review.save
      record_rate_limit!
      ReviewJsonSyncService.new.append(@review)

      respond_to do |format|
        format.html do
          flash[:notice] = "소중한 의견 감사합니다! 빠른 시일 내에 검토하겠습니다."
          redirect_to root_path
        end
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "review-form",
            partial: "reviews/thank_you"
          )
        end
        format.json { render json: @review.to_review_json, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "review-form",
            partial: "reviews/form",
            locals: { review: @review }
          )
        end
        format.json { render json: { errors: @review.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  private

  def review_params
    params.require(:review).permit(:rating, :body, :email, :channel)
  end

  def rate_limit_key
    "review_rate_#{request.remote_ip}"
  end

  def rate_limited?
    data = session[rate_limit_key]
    return false unless data

    window_start = data["window_start"]
    count = data["count"].to_i

    if Time.now.to_i - window_start.to_i > RATE_LIMIT_WINDOW
      session.delete(rate_limit_key)
      false
    else
      count >= RATE_LIMIT_COUNT
    end
  end

  def record_rate_limit!
    data = session[rate_limit_key]
    if data && Time.now.to_i - data["window_start"].to_i <= RATE_LIMIT_WINDOW
      session[rate_limit_key] = {
        "window_start" => data["window_start"],
        "count"        => data["count"].to_i + 1
      }
    else
      session[rate_limit_key] = {
        "window_start" => Time.now.to_i,
        "count"        => 1
      }
    end
  end
end
