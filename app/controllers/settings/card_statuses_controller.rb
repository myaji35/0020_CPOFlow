# frozen_string_literal: true

module Settings
  class CardStatusesController < BaseController
    # ISS-300: 카드 상태(시스템 메타) 변경은 manager 이상만
    before_action :require_manager!
    before_action :set_current_board
    before_action :set_card_status, only: %i[update destroy inline_rename]

    def index
      @card_statuses = @current_board.card_statuses.order(:position, :id)
      @themes        = CardStatusThemes::ALL
      @current_theme = CardStatusThemes.current_theme
      # 프리셋: 현재 테마가 감지되면 그 테마의 7색, 없으면 기존 12색 fallback
      @color_presets = CardStatusThemes.current_palette || CardStatusColorPresets::ALL
      @card_status ||= CardStatus.new
    end

    # POST /settings/card_statuses/apply_theme
    # 4개 테마(Pastel/Vivid/Mono/Corporate) 일괄 적용
    def apply_theme
      theme_key = params[:theme_key].to_s
      result = CardStatusThemes.apply!(theme_key)
      if result[:ok]
        redirect_to settings_card_statuses_path(board_id: @current_board.id),
                    notice: "#{result[:theme]} 테마 적용: #{result[:updated]}개 상태 색상 변경"
      else
        redirect_to settings_card_statuses_path(board_id: @current_board.id), alert: "테마 적용 실패: #{result[:error]}"
      end
    end

    def create
      # 편집 모달에서 editing_id가 전달되면 update로 분기
      if params[:editing_id].present?
        @card_status = CardStatus.find(params[:editing_id])
        if @card_status.update(card_status_params)
          redirect_to settings_card_statuses_path(board_id: @current_board.id), notice: "상태가 수정되었습니다."
        else
          prepare_index_vars
          render :index, status: :unprocessable_entity
        end
        return
      end

      @card_status = @current_board.card_statuses.build(card_status_params)
      if @card_status.save
        redirect_to settings_card_statuses_path(board_id: @current_board.id), notice: "상태가 추가되었습니다."
      else
        prepare_index_vars
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @card_status.update(card_status_params)
        redirect_to settings_card_statuses_path(board_id: @current_board.id), notice: "상태가 수정되었습니다."
      else
        prepare_index_vars
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
        redirect_to settings_card_statuses_path(board_id: @current_board.id), notice: "상태가 삭제되었습니다."
      else
        respond_to do |format|
          format.html { redirect_to settings_card_statuses_path(board_id: @current_board.id), alert: reason, status: :see_other }
          format.any  { render json: { status: "error", error: reason }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to settings_card_statuses_path(board_id: @current_board.id), alert: "삭제 실패."
    end

    def reorder
      ids = Array(params[:order]).map(&:to_i)
      CardStatus.transaction do
        ids.each_with_index do |id, idx|
          @current_board.card_statuses.where(id: id).update_all(position: idx + 1)
        end
      end
      render json: { status: "ok" }
    end

    private

    def set_current_board
      @current_board = if params[:board_id].present?
        KanbanBoard.find_by(id: params[:board_id])
      end
      @current_board ||= KanbanBoard.default_board.first || KanbanBoard.ensure_default!
    end

    def set_card_status
      @card_status = CardStatus.find(params[:id])
    end

    def prepare_index_vars
      @card_statuses = @current_board.card_statuses.order(:position, :id)
      @themes        = CardStatusThemes::ALL
      @current_theme = CardStatusThemes.current_theme
      @color_presets = CardStatusThemes.current_palette || CardStatusColorPresets::ALL
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
