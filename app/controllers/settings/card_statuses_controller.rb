# frozen_string_literal: true

module Settings
  class CardStatusesController < BaseController
    before_action :set_card_status, only: %i[update destroy inline_rename]

    def index
      @card_statuses = CardStatus.ordered
      @color_presets = CardStatusColorPresets::ALL
      @card_status ||= CardStatus.new
    end

    def create
      @card_status = CardStatus.new(card_status_params)
      if @card_status.save
        redirect_to settings_card_statuses_path, notice: "상태가 추가되었습니다."
      else
        @card_statuses = CardStatus.ordered
        @color_presets = CardStatusColorPresets::ALL
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @card_status.update(card_status_params)
        redirect_to settings_card_statuses_path, notice: "상태가 수정되었습니다."
      else
        @card_statuses = CardStatus.ordered
        @color_presets = CardStatusColorPresets::ALL
        render :index, status: :unprocessable_entity
      end
    end

    # 인라인 rename 전용 — name 하나만 수정
    def inline_rename
      if @card_status.update(name: params[:name])
        render json: { status: "ok", name: @card_status.name }
      else
        render json: { status: "error", errors: @card_status.errors.full_messages },
               status: :unprocessable_entity
      end
    end

    def destroy
      deletable = false
      reason = nil
      CardStatus.transaction do
        @card_status.lock!
        if @card_status.deletable?
          @card_status.destroy!
          deletable = true
        else
          reason = @card_status.is_system? ? "시스템 내장 상태는 삭제할 수 없습니다." : "이 상태를 사용 중인 카드 #{@card_status.orders.count}건이 있습니다."
        end
      end

      if deletable
        redirect_to settings_card_statuses_path, notice: "상태가 삭제되었습니다."
      else
        respond_to do |format|
          format.html { redirect_to settings_card_statuses_path, alert: reason, status: :see_other }
          format.any  { render json: { status: "error", error: reason }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to settings_card_statuses_path, alert: "삭제 실패."
    end

    def reorder
      ids = Array(params[:order]).map(&:to_i)
      CardStatus.transaction do
        ids.each_with_index do |id, idx|
          CardStatus.where(id: id).update_all(position: idx + 1)
        end
      end
      render json: { status: "ok" }
    end

    private

    def set_card_status
      @card_status = CardStatus.find(params[:id])
    end

    def card_status_params
      params.require(:card_status).permit(
        :key, :name, :bg_color, :border_color, :text_color,
        :is_default, :auto_priority, :auto_rule
      ).tap do |p|
        # is_system 은 API로 변경 불가 (seed에서만 설정)
        # is_default 변경 시 기존 default는 false로 리셋
        if p[:is_default] == "1" || p[:is_default] == true
          CardStatus.where(is_default: true).where.not(id: params[:id]).update_all(is_default: false)
        end
      end
    end
  end
end
