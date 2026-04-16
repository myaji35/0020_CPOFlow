# frozen_string_literal: true

module Settings
  class KanbanBoardsController < ApplicationController
    before_action :require_admin!
    before_action :set_board, only: %i[edit update destroy reorder duplicate]

    def index
      @boards = KanbanBoard.ordered.includes(:card_statuses, :orders)
    end

    def create
      @board = KanbanBoard.new(board_params)
      @board.position = KanbanBoard.maximum(:position).to_i + 1
      @board.owner = current_user
      if @board.save
        seed_default_columns(@board)
        redirect_to settings_card_statuses_path(board_id: @board.id), notice: "보드 '#{@board.name}'이 생성되었습니다. 블럭을 편집하세요."
      else
        @boards = KanbanBoard.ordered.includes(:card_statuses, :orders)
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @board.update(board_params)
        redirect_to settings_kanban_boards_path, notice: "보드가 수정되었습니다."
      else
        @boards = KanbanBoard.ordered.includes(:card_statuses, :orders)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      if @board.is_default?
        redirect_to settings_kanban_boards_path, alert: "기본 보드는 삭제할 수 없습니다."
      elsif @board.orders.not_archived.any?
        redirect_to settings_kanban_boards_path, alert: "활성 주문이 있는 보드는 삭제할 수 없습니다."
      else
        @board.destroy
        redirect_to settings_kanban_boards_path, notice: "보드가 삭제되었습니다."
      end
    end

    def reorder
      @board.update!(position: params[:position].to_i)
      head :ok
    end

    def duplicate
      new_board = @board.dup
      new_board.name = "#{@board.name} (복사)"
      new_board.is_default = false
      new_board.position = KanbanBoard.maximum(:position).to_i + 1
      new_board.save!
      @board.card_statuses.each do |cs|
        new_cs = cs.dup
        new_cs.kanban_board = new_board
        new_cs.save!
      end
      redirect_to settings_kanban_boards_path, notice: "보드가 복제되었습니다."
    end

    private

    def set_board
      @board = KanbanBoard.find(params[:id])
    end

    def board_params
      params.require(:kanban_board).permit(:name, :board_type, :description, :color_palette, :is_default)
    end

    def require_admin!
      redirect_to root_path, alert: "관리자만 접근할 수 있습니다." unless current_user&.admin?
    end

    # 새 보드에 기본 블럭 3개 자동 생성
    def seed_default_columns(board)
      palette = { "pastel" => %w[#DBEAFE #FEF3C7 #D1FAE5],
                  "vivid"  => %w[#3B82F6 #F59E0B #10B981],
                  "mono"   => %w[#E5E7EB #9CA3AF #4B5563],
                  "corporate" => %w[#EFF6FF #FFF7ED #ECFDF5] }
      colors = palette[board.color_palette] || palette["corporate"]
      [
        { key: "todo",        name: "할 일",   bg_color: colors[0], position: 0 },
        { key: "in_progress", name: "진행 중", bg_color: colors[1], position: 1 },
        { key: "completed",   name: "완료",    bg_color: colors[2], position: 2 }
      ].each do |attrs|
        board.card_statuses.create!(
          **attrs,
          border_color: "#D1D5DB",
          text_color: "#374151",
          is_system: false,
          is_default: attrs[:key] == "todo"
        )
      end
    end
  end
end
