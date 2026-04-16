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
        redirect_to settings_kanban_boards_path, notice: "보드 '#{@board.name}'이 생성되었습니다."
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
  end
end
