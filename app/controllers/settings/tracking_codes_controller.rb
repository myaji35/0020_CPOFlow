# frozen_string_literal: true

module Settings
  class TrackingCodesController < BaseController
    before_action :require_admin!
    before_action :set_tracking_code, only: %i[update destroy]

    def index
      @tracking_codes = TrackingCode.ordered
      @tracking_code  = TrackingCode.new
    end

    def create
      @tracking_code = TrackingCode.new(tracking_code_params)
      @tracking_code.position = (TrackingCode.maximum(:position) || 0) + 1
      @tracking_code.short_label = @tracking_code.code.to_s[0] if @tracking_code.short_label.blank? && @tracking_code.code.present?

      if @tracking_code.save
        redirect_to settings_tracking_codes_path, notice: "관리번호 '#{@tracking_code.code}'이(가) 추가되었습니다."
      else
        @tracking_codes = TrackingCode.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @tracking_code.update(tracking_code_params)
        redirect_to settings_tracking_codes_path, notice: "관리번호가 수정되었습니다."
      else
        @tracking_codes = TrackingCode.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @tracking_code.destroy
      redirect_to settings_tracking_codes_path, notice: "관리번호가 삭제되었습니다."
    end

    def reorder
      ids = params[:ids]
      return head(:bad_request) unless ids.is_a?(Array)
      ids.each_with_index do |id, idx|
        TrackingCode.where(id: id).update_all(position: idx)
      end
      head :ok
    end

    private

    def set_tracking_code
      @tracking_code = TrackingCode.find(params[:id])
    end

    def tracking_code_params
      params.require(:tracking_code).permit(:code, :short_label, :name, :color, :active)
    end

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근할 수 있습니다." unless current_user&.admin?
    end
  end
end
