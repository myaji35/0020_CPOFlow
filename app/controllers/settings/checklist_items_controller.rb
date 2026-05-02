# frozen_string_literal: true

# ISS-330: RFP 분석 표준 체크리스트 관리
module Settings
  class ChecklistItemsController < BaseController
    before_action :require_admin!
    before_action :set_item, only: %i[update destroy]

    def index
      @items = ChecklistItem.ordered
      @item  = ChecklistItem.new(active: true)
    end

    def create
      @item = ChecklistItem.new(item_params)
      assign_allowed_values(@item, params.dig(:checklist_item, :allowed_values_text))
      @item.position = (ChecklistItem.maximum(:position) || 0) + 10

      if @item.save
        redirect_to settings_checklist_items_path, notice: "체크리스트 '#{@item.code}' 추가됨"
      else
        @items = ChecklistItem.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def update
      assign_allowed_values(@item, params.dig(:checklist_item, :allowed_values_text))
      if @item.update(item_params)
        redirect_to settings_checklist_items_path, notice: "체크리스트 수정됨"
      else
        @items = ChecklistItem.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @item.destroy
      redirect_to settings_checklist_items_path, notice: "체크리스트 삭제됨"
    end

    private

    def set_item
      @item = ChecklistItem.find(params[:id])
    end

    def item_params
      params.require(:checklist_item).permit(:code, :name, :name_en, :category, :prompt_hint, :required, :active, :position)
    end

    # 사용자가 입력한 콤마구분 텍스트 → JSON 배열
    def assign_allowed_values(item, text)
      return if text.nil?
      arr = text.to_s.split(",").map(&:strip).reject(&:empty?)
      item.allowed_values_array = arr
    end

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근 가능합니다." unless current_user&.admin?
    end
  end
end
