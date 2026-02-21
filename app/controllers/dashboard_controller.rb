class DashboardController < ApplicationController
  def index
    @total_active   = Order.active.count
    @overdue_count  = Order.overdue.count
    @urgent_count   = Order.urgent.count
    @delivered_this_month = Order.delivered
                                 .where(updated_at: Time.current.beginning_of_month..)
                                 .count

    @urgent_orders  = Order.urgent.by_due_date.limit(5).includes(:assignees)
    @recent_orders  = Order.order(created_at: :desc).limit(8).includes(:assignees, :tasks)

    # Returns { "inbox" => N, "reviewing" => N, ... } (string keys from enum)
    @kanban_counts  = Order.group(:status).count

    # Google Sheets 동기화 상태
    @last_sync      = SheetsSyncLog.recent.first
    @sheets_mock    = Sheets::SheetsService.new.mock_mode?
  end

  def sync_sheets
    SheetsSyncJob.perform_later
    redirect_to dashboard_path, notice: "Google Sheets 동기화가 시작되었습니다."
  end
end
