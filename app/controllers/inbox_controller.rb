class InboxController < ApplicationController
  def index
    # All orders that came from emails, sorted newest first
    @all_orders  = Order.where.not(original_email_from: [nil, ""])
                        .order(created_at: :desc)
                        .includes(:user, :assignees)
                        .limit(100)

    # Subset: only inbox-stage orders that have an email source (for body pane)
    @rfq_orders  = Order.where(status: :inbox)
                        .where.not(original_email_from: [nil, ""])
                        .by_due_date
                        .includes(:user, :assignees)
                        .limit(50)
  end

  def show
    @order = Order.find_by(source_email_id: params[:id]) ||
             Order.find(params[:id])
  end

  def convert_to_order
    @order = Order.find(params[:id])
    if @order.update(status: :reviewing)
      Activity.create!(order: @order, user: current_user, action: "moved_to_kanban")
      redirect_to kanban_path, notice: "Order moved to Kanban — Under Review."
    else
      redirect_back fallback_location: inbox_path, alert: "Failed to convert."
    end
  end

  # Manual sync trigger (called from Inbox UI "Sync" button)
  def sync
    accounts = current_user.email_accounts.where(connected: true)
    if accounts.any?
      accounts.each { |acc| EmailSyncJob.perform_later(account_id: acc.id) }
      render json: { status: "ok", message: "Sync queued for #{accounts.count} account(s)" }
    else
      render json: { status: "error", message: "No connected accounts" }, status: :unprocessable_entity
    end
  end
end
