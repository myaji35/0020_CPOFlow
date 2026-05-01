# frozen_string_literal: true

module Settings
  class KanbanColumnsController < BaseController
    before_action :require_admin!
    before_action :set_current_board
    before_action :set_kanban_column, only: %i[update destroy]

    def index
      @kanban_columns = @current_board.kanban_columns.ordered
      @kanban_column  = KanbanColumn.new
    end

    def create
      @kanban_column = @current_board.kanban_columns.build(kanban_column_params)
      @kanban_column.position = @current_board.kanban_columns.maximum(:position).to_i + 1

      if @kanban_column.save
        redirect_to settings_kanban_columns_path(board_id: @current_board.id),
                    notice: "블럭 '#{@kanban_column.name}'이(가) 추가되었습니다."
      else
        @kanban_columns = @current_board.kanban_columns.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @kanban_column.update(kanban_column_params)
        redirect_to settings_kanban_columns_path(board_id: @current_board.id),
                    notice: "블럭이 수정되었습니다."
      else
        @kanban_columns = @current_board.kanban_columns.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      # 향후 칸반 칼럼 기반 렌더링 시 카드 체크 로직 추가 가능
      @kanban_column.destroy
      redirect_to settings_kanban_columns_path(board_id: @current_board.id),
                  notice: "블럭이 삭제되었습니다."
    end

    def reorder
      ids = params[:ids]
      return head(:bad_request) unless ids.is_a?(Array)

      ids.each_with_index do |id, idx|
        @current_board.kanban_columns.where(id: id).update_all(position: idx)
      end
      head :ok
    end

    private

    def set_current_board
      @current_board = if params[:board_id].present?
                         KanbanBoard.find(params[:board_id])
      else
                         KanbanBoard.default_board.first || KanbanBoard.ensure_default!
      end
    end

    def set_kanban_column
      @kanban_column = @current_board.kanban_columns.find(params[:id])
    end

    def kanban_column_params
      params.require(:kanban_column).permit(:name, :key, :color, :is_final, :wip_limit)
    end

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근할 수 있습니다." unless current_user&.admin?
    end
  end
end
